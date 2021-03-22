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

/// The request is sent from the client to the server to resolve the callers for
/// a given call hierarchy item. It is only issued if a server registers for the
/// `textDocument/prepareCallHierarchy` request.
public struct CallHierarchyIncomingCallsRequest: RequestType {
  public static let method: String = "callHierarchy/incomingCalls"
  public typealias Response = [CallHierarchyIncomingCall]?

  public var item: CallHierarchyItem

  public init(item: CallHierarchyItem) {
    self.item = item
  }
}

/// Represents a caller (an incoming call) - an item that makes a call of the original `item`.
public struct CallHierarchyIncomingCall: ResponseType, Hashable {
  /// The item that makes the call.
  public var from: CallHierarchyItem

  /// The range(s) of calls inside the caller (the item denoted by `from`).
  @CustomCodable<PositionRangeArray>
  public var fromRanges: [Range<Position>]

  public init(from: CallHierarchyItem, fromRanges: [Range<Position>]) {
    self.from = from
    self.fromRanges = fromRanges
  }
}
