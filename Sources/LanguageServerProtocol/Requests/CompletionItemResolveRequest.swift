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

public struct CompletionItemResolveRequest: RequestType {
  public static var method: String = "completionItem/resolve"
  public typealias Response = CompletionItem

  public var item: CompletionItem

  public init(item: CompletionItem) {
    self.item = item
  }

  public init(from decoder: Decoder) throws {
    self.item = try CompletionItem(from: decoder)
  }

  public func encode(to encoder: Encoder) throws {
    try self.item.encode(to: encoder)
  }
}
