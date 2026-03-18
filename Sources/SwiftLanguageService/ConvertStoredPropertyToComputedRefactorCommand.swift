//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftSyntax

package struct ConvertStoredPropertyToComputedCommand: SwiftCommand, Equatable, Sendable {

  package static let identifier: String =
    "semantic.refactor.convertStoredPropertyToComputed"

  package var title: String
  let uri: DocumentURI
  let offset: Int

  init(
    title: String = "Convert Stored Property to Computed Property",
    uri: DocumentURI,
    offset: Int
  ) {
    self.title = title
    self.uri = uri
    self.offset = offset
  }

  init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard
      case .string(let uriString) = dictionary["uri"],
      case .int(let offsetInt) = dictionary["offset"],
      let uri = try? DocumentURI(string: uriString)
    else {
      return nil
    }

    if case .string(let titleString) = dictionary["title"] {
      self.title = titleString
    } else {
      self.title = "Convert Stored Property to Computed Property"
    }

    self.uri = uri
    self.offset = offsetInt
  }

  func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      "title": .string(title),
      "uri": .string(uri.stringValue),
      "offset": .int(offset),
    ])
  }

  func run(
    languageService: SwiftLanguageService
  ) async throws -> WorkspaceEdit {
    return try await languageService
      .executeConvertStoredPropertyToComputed(uri: uri, offset: offset)
      ?? WorkspaceEdit(changes: [:])
  }
}
