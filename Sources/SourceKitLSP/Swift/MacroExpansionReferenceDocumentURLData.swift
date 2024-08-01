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

import Foundation
import LanguageServerProtocol
import RegexBuilder

/// Represents url of macro expansion reference document as follows:
/// `sourcekit-lsp://swift-macro-expansion/LaCb-LcCd.swift?primaryFilePath=&fromLine=&fromColumn=&toLine=&toColumn=&bufferName=`
///
/// Here,
///  - `LaCb-LcCd.swift`, the `displayName`, represents where the macro will expand to or
///    replace in the source file (i.e. `macroExpansionEditRange`)
///  - `primaryFilePath` denoting the URL of the source file
///  - `fromLine`, `fromColumn`, `toLine`, `toColumn` represents the cursor's `selectionRange`
///  - `bufferName` denotes the buffer name of the specific macro expansion edit
package struct MacroExpansionReferenceDocumentURLData {
  package static let documentType = "swift-macro-expansion"

  package var primaryFileURL: URL
  package var selectionRange: Range<Position>
  package var bufferName: String
  package var macroExpansionEditRange: Range<Position>

  package init(
    macroExpansionEditRange: Range<Position>,
    primaryFileURL: URL,
    selectionRange: Range<Position>,
    bufferName: String
  ) {
    self.primaryFileURL = primaryFileURL
    self.selectionRange = selectionRange
    self.bufferName = bufferName
    self.macroExpansionEditRange = macroExpansionEditRange
  }

  package var displayName: String {
    "L\(macroExpansionEditRange.lowerBound.line + 1)C\(macroExpansionEditRange.lowerBound.utf16index + 1)-L\(macroExpansionEditRange.upperBound.line + 1)C\(macroExpansionEditRange.upperBound.utf16index + 1).swift"
  }

  package var queryItems: [URLQueryItem] {
    [
      URLQueryItem(name: Parameters.primaryFilePath, value: primaryFileURL.path(percentEncoded: false)),
      URLQueryItem(name: Parameters.fromLine, value: String(selectionRange.lowerBound.line)),
      URLQueryItem(name: Parameters.fromColumn, value: String(selectionRange.lowerBound.utf16index)),
      URLQueryItem(name: Parameters.toLine, value: String(selectionRange.upperBound.line)),
      URLQueryItem(name: Parameters.toColumn, value: String(selectionRange.upperBound.utf16index)),
      URLQueryItem(name: Parameters.bufferName, value: bufferName),
    ]
  }

  package init(displayName: String, queryItems: [URLQueryItem]) throws {
    guard let primaryFilePath = queryItems.last { $0.name == Parameters.primaryFilePath }?.value,
      let fromLine = Int(queryItems.last { $0.name == Parameters.fromLine }?.value ?? ""),
      let fromColumn = Int(queryItems.last { $0.name == Parameters.fromColumn }?.value ?? ""),
      let toLine = Int(queryItems.last { $0.name == Parameters.toLine }?.value ?? ""),
      let toColumn = Int(queryItems.last { $0.name == Parameters.toColumn }?.value ?? ""),
      let bufferName = queryItems.last { $0.name == Parameters.bufferName }?.value
    else {
      throw ReferenceDocumentURLError(description: "Invalid queryItems for macro expansion reference document url")
    }

    guard let primaryFileURL = URL(string: "file://\(primaryFilePath)") else {
      throw ReferenceDocumentURLError(
        description: "Unable to parse source file url"
      )
    }

    self.primaryFileURL = primaryFileURL
    self.selectionRange =
      Position(line: fromLine, utf16index: fromColumn)..<Position(line: toLine, utf16index: toColumn)
    self.bufferName = bufferName
    self.macroExpansionEditRange = try Self.parse(displayName: displayName)
  }

  package var primaryFile: DocumentURI {
    DocumentURI(primaryFileURL)
  }

  private struct Parameters {
    static let primaryFilePath = "primaryFilePath"
    static let fromLine = "fromLine"
    static let fromColumn = "fromColumn"
    static let toLine = "toLine"
    static let toColumn = "toColumn"
    static let bufferName = "bufferName"
  }

  private static func parse(displayName: String) throws -> Range<Position> {
    let regex = Regex {
      "L"
      TryCapture {
        OneOrMore(.digit)
      } transform: {
        Int($0)
      }
      "C"
      TryCapture {
        OneOrMore(.digit)
      } transform: {
        Int($0)
      }
      "-L"
      TryCapture {
        OneOrMore(.digit)
      } transform: {
        Int($0)
      }
      "C"
      TryCapture {
        OneOrMore(.digit)
      } transform: {
        Int($0)
      }
      ".swift"
    }

    guard let match = try? regex.wholeMatch(in: displayName) else {
      throw ReferenceDocumentURLError(
        description: "Wrong format of display name of macro expansion reference document: '\(displayName)'"
      )
    }

    return Position(
      line: match.1 - 1,
      utf16index: match.2 - 1
    )..<Position(
      line: match.3 - 1,
      utf16index: match.4 - 1
    )
  }
}
