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

import Foundation
import LSPLogging

/// A request object, wrapping the parameters of a `RequestType` and tracking its state.
public final class Request<R: RequestType> {

  public typealias Params = R

  public typealias Response = R.Response

  /// The request id from the client.
  public let id: RequestID

  /// The client of the request.
  public let clientID: ObjectIdentifier

  /// The request parameters.
  public let params: Params

  private var replyBlock: (LSPResult<Response>) -> Void

  /// Whether a reply has been made. Every request must reply exactly once.
  private var replied: Bool = false {
    willSet {
      precondition(replied == false, "replied to \(id) more than once")
    }
  }

  /// The request's cancellation state.
  public let cancellationToken: CancellationToken

  public init(
    _ request: Params,
    id: RequestID,
    clientID: ObjectIdentifier,
    cancellation: CancellationToken,
    reply: @escaping (LSPResult<Response>) -> Void
  ) {
    self.id = id
    self.clientID = clientID
    self.params = request
    self.cancellationToken = cancellation
    self.replyBlock = reply
  }

  deinit {
    precondition(replied, "request \(id) never received a reply")
  }

  /// Reply to the request with `result`.
  ///
  /// This must be called exactly once for each request.
  public func reply(_ result: LSPResult<Response>) {
    replied = true
    replyBlock(result)
  }

  /// Reply to the request with `.success(result)`.
  public func reply(_ result: Response) {
    reply(.success(result))
  }

  /// Whether the result has been cancelled.
  public var isCancelled: Bool { return cancellationToken.isCancelled }
}

fileprivate extension Encodable {
  var prettyPrintJSON: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting.insert(.prettyPrinted)
    guard let data = try? encoder.encode(self) else {
      return "\(self)"
    }
    guard let string = String(data: data, encoding: .utf8) else {
      return "\(self)"
    }
    // Don't escape '/'. Most JSON readers don't need it escaped and it makes
    // paths a lot easier to read and copy-paste.
    return string.replacingOccurrences(of: "\\/", with: "/")
  }
}

extension Request: CustomStringConvertible, CustomLogStringConvertible {
  public var description: String {
    return """
      \(R.method)
      \(params.prettyPrintJSON)
      """
  }

  public var redactedDescription: String {
    // FIXME: (logging) Log the non-critical parts of the request
    return "Request<\(R.method)>"
  }
}

fileprivate struct AnyNotificationType: CustomLogStringConvertible {
  let notification: any NotificationType

  public var description: String {
    return """
      \(type(of: notification))
      \(notification.prettyPrintJSON)
      """
  }

  public var redactedDescription: String {
    // FIXME: (logging) Log the non-critical parts of the notification
    return "\(type(of: notification))"
  }
}

extension NotificationType {
  public var forLogging: CustomLogStringConvertibleWrapper {
    return AnyNotificationType(notification: self).forLogging
  }
}
