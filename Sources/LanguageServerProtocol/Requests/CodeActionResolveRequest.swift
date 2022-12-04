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

public struct CodeActionResolveRequest: RequestType {
  public static var method: String = "codeAction/resolve"
  public typealias Response = CodeAction

  public var codeAction: CodeAction

  public init(codeAction: CodeAction) {
    self.codeAction = codeAction
  }

  public init(from decoder: Decoder) throws {
    self.codeAction = try CodeAction(from: decoder)
  }

  public func encode(to encoder: Encoder) throws {
    try self.codeAction.encode(to: encoder)
  }
}
