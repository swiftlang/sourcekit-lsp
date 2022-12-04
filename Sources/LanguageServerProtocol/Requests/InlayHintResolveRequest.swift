//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct InlayHintResolveRequest: RequestType {
  public static var method: String = "inlayHint/resolve"
  public typealias Response = InlayHint

  public var inlayHint: InlayHint

  public init(inlayHint: InlayHint) {
    self.inlayHint = inlayHint
  }

  public init(from decoder: Decoder) throws {
    self.inlayHint = try InlayHint(from: decoder)
  }

  public func encode(to encoder: Encoder) throws {
    try inlayHint.encode(to: encoder)
  }
}
