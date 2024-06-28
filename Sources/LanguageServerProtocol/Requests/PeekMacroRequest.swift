//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct PeekMacroRequest: RequestType {
  public static let method: String = "sourcekit-lsp/peekMacro"
  public typealias Response = PeekMacroResponse

  public var macroExpansion: MacroExpansion
  public var peekLocation: Position

  public init(macroExpansion: MacroExpansion, peekLocation: Position) {
    self.macroExpansion = macroExpansion
    self.peekLocation = peekLocation
  }
}

public struct MacroExpansion: Codable, Sendable {
  public var expansionURIs: [DocumentURI]

  public init(expansionURIs: [DocumentURI]) {
    self.expansionURIs = expansionURIs
  }
}

public struct PeekMacroResponse: ResponseType {
  public var success: Bool
  public var failureReason: String?
}

