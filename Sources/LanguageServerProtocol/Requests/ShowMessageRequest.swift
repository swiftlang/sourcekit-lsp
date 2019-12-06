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

/// Request from the server containing a message for the client to display.
///
/// - Parameters:
///   - type: The kind of message.
///   - message: The contents of the message.
///   - actions: Action items which the user may select (up to 1).
///
/// - Returns: The action selected by the user, if any.
public struct ShowMessageRequest: RequestType, Hashable {
  public static let method: String = "window/showMessageRequest"
  public typealias Response = MessageActionItem?

  /// The kind of message.
  public var type: WindowMessageType

  /// The contents of the message.
  public var message: String

  /// The action items to present with the message.
  public var actions: [MessageActionItem]?

  public init(
    type: WindowMessageType,
    message: String,
    actions: [MessageActionItem]?)
  {
    self.type = type
    self.message = message
    self.actions = actions
  }
}

/// Message action item that the user may select.
public struct MessageActionItem: ResponseType, Hashable {

  /// The title of the item.
  public var title: String

  public init(title: String) {
    self.title = title
  }
}
