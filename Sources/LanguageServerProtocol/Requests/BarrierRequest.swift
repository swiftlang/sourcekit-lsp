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

/// A no-op request that ensures all previous notifications and requests have been handled before any message
/// after the barrier request is handled.
public struct BarrierRequest: RequestType {
  public static var method: String = "workspace/_barrier"
  public typealias Response = VoidResponse

  public init() {}
}
