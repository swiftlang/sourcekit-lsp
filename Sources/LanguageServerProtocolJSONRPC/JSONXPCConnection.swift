//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if os(macOS)

import SKSupport
import LanguageServerProtocol
import Dispatch
import Foundation
import XPC

/// A connection between a message handler (e.g. language server) in the same process as the connection object and a remote message handler (e.g. language client) that may run in another process using JSON RPC messages sent over a pair of in/out file descriptors.
///
/// For example, inside a language server, the `JSONXPCConnection` takes the language service implemenation as its `receiveHandler` and itself provides the client connection for sending notifications and callbacks.
public final class JSONXPCConnection: Connection {
    let conn: xpc_connection_t
    let queue: DispatchQueue = DispatchQueue(label: "jsonxpc-queue", qos: .userInitiated)
    var receiveHandler: MessageHandler? = nil

    enum State {
        case created, running, closed
    }

    /// Current state of the connection, used to ensure correct usage.
    var state: State

    private var _nextRequestID: Int = 0

    struct OutstandingRequest {
        var requestType: _RequestType.Type
        var responseType: ResponseType.Type
        var queue: DispatchQueue
        var replyHandler: (LSPResult<Any>) -> Void
    }

    /// The set of currently outstanding outgoing requests along with information about how to decode and handle their responses.
    var outstandingRequests: [RequestID: OutstandingRequest] = [:]

    /// Request id for the next outgoing request.
    func nextRequestID() -> RequestID {
        _nextRequestID += 1
        return .number(_nextRequestID)
    }

    public init(xpc_service_name: String) {
        let queue = self.queue
        conn = xpc_service_name.withCString { xpc_connection_create($0, queue) }
        state = .created
    }

    deinit {
        assert(state == .closed)
    }

    public func close() {
        guard state == .running else { return }
        // Break the retain cycle in the connection.
        if let pointer = xpc_connection_get_context(conn) {
            Unmanaged<JSONXPCConnection>.fromOpaque(pointer).release()
        }
        xpc_connection_cancel(conn)
        state = .closed
    }

    public func start(receiveHandler: MessageHandler) {
        precondition(state == .created)
        state = .running
        self.receiveHandler = receiveHandler

        xpc_connection_set_context(conn, Unmanaged.passRetained(self).toOpaque())
        xpc_connection_set_event_handler(conn, { (event: xpc_object_t) in
            let type = xpc_get_type(event)

            if type == XPC_TYPE_ERROR {
                if event.isEqual(XPC_ERROR_CONNECTION_INVALID) {
                    log("invalid XPC connection", level: .error)
                }
                if event.isEqual(XPC_ERROR_CONNECTION_INTERRUPTED) {
                    log("interrupted XPC connection", level: .error)
                    // FIXME: Handle interrupted connections.
                }
                return
            }

            if type != XPC_TYPE_DICTIONARY {
                log("ignoring unknown XPC message of type \(type)", level: .warning)
                return
            }
            guard let conn = xpc_dictionary_get_remote_connection(event),
                let pointer = xpc_connection_get_context(conn) else {
                fatalError("failed to get XPC connection context")
            }
            let instance = Unmanaged<JSONXPCConnection>.fromOpaque(pointer).takeUnretainedValue()

            var length = 0
            guard let result = "LSP".withCString ({ (lsp_s: UnsafePointer<CChar>) -> UnsafeRawPointer? in
                return withUnsafeMutablePointer(to: &length) {
                    xpc_dictionary_get_data(event, lsp_s, $0)
                }
            }) else {
                log("ignoring malformed XPC message", level: .error)
                return
            }
            let data = Data(bytes: result, count: length)

            do {
                let decoder = JSONDecoder()

                // Setup callback for response type.
                decoder.userInfo[.responseTypeCallbackKey] = { id in
                    guard let outstanding = self.outstandingRequests[id] else {
                        log("Unknown request for \(id)", level: .error)
                        return nil
                    }
                    return outstanding.responseType
                } as Message.ResponseTypeCallback
                let message = try decoder.decode(Message.self, from: data)
                instance.handle(message)
            } catch let error as MessageDecodingError {
                switch error.messageKind {
                case .request:
                    if let id = error.id {
                        instance.send { encoder in
                            try encoder.encode(Message.errorResponse(ResponseError(error), id: id))
                        }
                        return
                    }
                case .response:
                    if let id = error.id {
                        if let outstanding = instance.outstandingRequests.removeValue(forKey: id) {
                            outstanding.replyHandler(.failure(ResponseError(error)))
                        } else {
                            log("error in response to unknown request \(id) \(error)", level: .error)
                        }
                        return
                    }
                case .notification:
                    if error.code == .methodNotFound {
                        log("ignoring unknown notification \(error)")
                        return
                    }
                case .unknown:
                    break
                }
                // FIXME: graceful shutdown?
                fatalError("fatal error encountered decoding message \(error)")
            } catch {
                // FIXME: graceful shutdown?
                fatalError("fatal error encountered for XPC message \(error)")
            }
        })
        xpc_connection_resume(conn)
    }

    func handle(_ message: Message) {
        switch message {
        case .response(let response, id: let id):
            guard let outstanding = outstandingRequests.removeValue(forKey: id) else {
                log("Unknown request for \(id)", level: .error)
                return
            }
            outstanding.replyHandler(.success(response))
        case .errorResponse(let error, id: let id):
            guard let outstanding = outstandingRequests.removeValue(forKey: id) else {
                log("Unknown request for \(id)", level: .error)
                return
            }
            outstanding.replyHandler(.failure(error))
        case .notification(let notification):
            notification._handle(receiveHandler!, connection: self)
        case .request(let request, id: let id):
            request._handle(receiveHandler!, id: id, connection: self)
        }
    }

    func readyToSend() -> Bool {
        precondition(state != .created, "tried to send message before calling start")
        return state == .running
    }

    func send(messageData data: Data) {
        let dict = xpc_dictionary_create(nil, nil, 0)
        "LSP".withCString {
            let lsp_s = $0
            data.withUnsafeBytes {
                xpc_dictionary_set_data(dict, lsp_s, $0, data.count)
            }
        }
        xpc_connection_send_message(conn, dict)
    }

    func send(encoding: (JSONEncoder) throws -> Data) {
        guard readyToSend() else { return }

        let encoder = JSONEncoder()

        let data: Data
        do {
            data = try encoding(encoder)
        } catch {
            // FIXME: attempt recovery?
            fatalError("unexpected error while encoding response: \(error)")
        }

        send(messageData: data)
    }
}

extension JSONXPCConnection: _IndirectConnection {
    // MARK: Connection interface
    public func send<Notification>(_ notification: Notification) where Notification: NotificationType {
        guard readyToSend() else { return }
        send { encoder in
            return try encoder.encode(Message.notification(notification))
        }
    }

    public func send<Request>(_ request: Request, queue: DispatchQueue, reply: @escaping (LSPResult<Request.Response>) -> Void) -> RequestID where Request: RequestType {

        let id: RequestID = self.queue.sync {
            let id = nextRequestID()

            guard readyToSend() else {
                reply(.failure(.cancelled))
                return id
            }

            outstandingRequests[id] = OutstandingRequest(
                requestType: Request.self,
                responseType: Request.Response.self,
                queue: queue,
                replyHandler: { anyResult in
                    queue.async {
                        reply(anyResult.map { $0 as! Request.Response })
                    }
            })
            return id
        }

        send { encoder in
            return try encoder.encode(Message.request(request, id: id))
        }

        return id
    }

    public func sendReply<Response>(_ response: LSPResult<Response>, id: RequestID) where Response: ResponseType {
        guard readyToSend() else { return }

        send { encoder in
            switch response {
            case .success(let result):
                return try encoder.encode(Message.response(result, id: id))
            case .failure(let error):
                return try encoder.encode(Message.errorResponse(error, id: id))
            }
        }
    }
}

#endif
