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

import Dispatch

public protocol MessageType: Codable {}

/// `RequestType` with no associated type or same-type requirements. Most users should prefer
/// `RequestType`.
public protocol _RequestType: MessageType {

  /// The name of the request.
  static var method: String { get }

  /// *Implementation detail*. Dispatch `self` to the given handler and reply on `connection`.
  /// Only needs to be declared as a protocol requirement of `_RequestType` so we can call the implementation on `RequestType` from the underscored type.
  func _handle(
    _ handler: MessageHandler,
    id: RequestID,
    connection: Connection,
    reply: @escaping (LSPResult<ResponseType>, RequestID) -> Void
  )
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
}

/// A response.
public protocol ResponseType: MessageType {}

extension RequestType {
  public func _handle(
    _ handler: MessageHandler,
    id: RequestID,
    connection: Connection,
    reply: @escaping (LSPResult<ResponseType>, RequestID) -> Void
  ) {
    handler.handle(self, id: id, from: ObjectIdentifier(connection)) { response in
      reply(response.map({ $0 as ResponseType }), id)
    }
  }
}

extension NotificationType {
  public func _handle(_ handler: MessageHandler, connection: Connection) {
    handler.handle(self, from: ObjectIdentifier(connection))
  }
}

/// A `textDocument/*` notification, which takes a text document identifier
/// indicating which document it operates in or on.
public protocol TextDocumentNotification: NotificationType {
  var textDocument: TextDocumentIdentifier { get }
}

/// A `textDocument/*` request, which takes a text document identifier
/// indicating which document it operates in or on.
public protocol TextDocumentRequest: RequestType {
  var textDocument: TextDocumentIdentifier { get }
}
