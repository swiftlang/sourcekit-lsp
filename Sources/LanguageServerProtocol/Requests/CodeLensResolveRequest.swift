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

/// The code lens resolve request is sent from the client to the server to resolve the command for a given code lens item.
public struct CodeLensResolveRequest: RequestType {
  public static var method: String = "codeLens/resolve"
  public typealias Response = CodeLens

  public var codeLens: CodeLens

  public init(codeLens: CodeLens) {
    self.codeLens = codeLens
  }

  public init(from decoder: Decoder) throws {
    self.codeLens = try CodeLens(from: decoder)
  }

  public func encode(to encoder: Encoder) throws {
    try codeLens.encode(to: encoder)
  }
}
