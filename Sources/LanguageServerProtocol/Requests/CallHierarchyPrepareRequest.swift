//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The call hierarchy request is sent from the client to the server to return a call hierarchy for the
/// language element of the given text document positions.
///
/// The call hierarchy requests are executed in two steps:
/// 1. A call hierarchy item is resolved for the given text document position
///   (via `textDocument/prepareCallHierarchy`)
/// 2. The incoming or outgoing call hierarchy items are resolved for a call hierarchy item
///   (via `callHierarchy/incomingCalls` or `callHierarchy/outgoingCalls`)
public struct CallHierarchyPrepareRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/prepareCallHierarchy"
  public typealias Response = [CallHierarchyItem]?

  /// The document in which to prepare the call hierarchy items.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to prepare the call hierarchy items.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}
