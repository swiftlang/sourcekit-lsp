//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public protocol MessageType: Codable {}

/// `RequestType` with no associated type or same-type requirements. Most users should prefer `RequestType`.
public protocol _RequestType: MessageType {

  /// The name of the request.
  static var method: String { get }

  /// *Implementation detail*. Dispatch `self` to the given handler and reply on `connection`.
  func _handle(_ handler: MessageHandler, id: RequestID, connection: _IndirectConnection)
}

/// A request, which must have a unique `method` name as well as an associated response type.
public protocol RequestType: _RequestType {

  /// The type of of the response to this request.
  associatedtype Response: ResponseType
}

/// A notification, which must have a unique `method` name.
public protocol NotificationType: MessageType {

  /// The name of the request.
  static var method: String { get }

  /// *Implementation detail*. Dispatch `self` to the given handler.
  func _handle(_: MessageHandler, connection: Connection)
}

/// A response.
public protocol ResponseType: MessageType {}

extension RequestType {
  public func _handle(_ handler: MessageHandler, id: RequestID, connection: _IndirectConnection) {
    handler.handle(self, id: id, from: ObjectIdentifier(connection)) { response in
      connection.sendReply(response, id: id)
    }
  }
}

extension NotificationType {
  public func _handle(_ handler: MessageHandler, connection: Connection) {
    handler.handle(self, from: ObjectIdentifier(connection))
  }
}

public protocol TextDocumentRequest: RequestType {
  var textDocument: TextDocumentIdentifier { get }
}