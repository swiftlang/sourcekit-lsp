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

/// The request is sent from the client to the server to resolve callees for a given call hierarchy item.
/// It is only issued if a server registers for the `textDocument/prepareCallHierarchy` request.
public struct CallHierarchyOutgoingCallsRequest: RequestType {
  public static let method: String = "callHierarchy/outgoingCalls"
  public typealias Response = [CallHierarchyOutgoingCall]?

  public var item: CallHierarchyItem

  public init(item: CallHierarchyItem) {
    self.item = item
  }
}

/// Represents a callee (an outgoing call) - an item that is called by the original `item`.
public struct CallHierarchyOutgoingCall: ResponseType, Hashable {
  /// The item that is called.
  public var to: CallHierarchyItem

  /// The range(s) at which this item is called by the caller (the item inside
  /// the `callHierarchy/outgoingCalls` request).
  @CustomCodable<PositionRangeArray>
  public var fromRanges: [Range<Position>]

  public init(to: CallHierarchyItem, fromRanges: [Range<Position>]) {
    self.to = to
    self.fromRanges = fromRanges
  }
}
