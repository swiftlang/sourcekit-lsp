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

#if compiler(>=6)
package import Foundation
package import LanguageServerProtocol
import RegexBuilder
#else
import Foundation
import LanguageServerProtocol
import RegexBuilder
#endif

/// Represents url of macro expansion reference document as follows:
/// `sourcekit-lsp://swift-macro-expansion/LaCb-LcCd.swift?fromLine=&fromColumn=&toLine=&toColumn=&bufferName=&parent=`
///
/// Here,
///  - `LaCb-LcCd.swift`, the `displayName`, represents where the macro will expand to or
///    replace in the source file (i.e. `macroExpansionEditRange`)
///  - `fromLine`, `fromColumn`, `toLine`, `toColumn` represents the cursor's selection range in
///    its `parent` (i.e. `parentSelectionRange`)
///  - `bufferName` denotes the buffer name of the specific macro expansion edit
///  - `parent` denoting the URI of the document from which the macro was expanded. For a first-level macro expansion,
///    this is a file URI. For nested macro expansions, this is a `sourcekit-lsp://swift-macro-expansion` URL.
package struct MacroExpansionReferenceDocumentURLData: ReferenceURLData {
  package static let documentType = "swift-macro-expansion"

  /// The document from which this macro was expanded. For first-level macro expansions, this is a file URL. For
  /// second-level macro expansions, this is a `sourcekit-lsp://swift-macro-expansion/` URL, third-level macro
  /// expansions are a `sourcekit-lsp:` URL that themselves have a `sourcekit-lsp:` URL as their parent.
  package var parent: DocumentURI

  /// The range that was selected in `parent` when the macro was expanded.
  package var parentSelectionRange: Range<Position>

  /// ## Example
  ///
  /// User's source File:
  /// URL: `file:///path/to/swift_file.swift`
  /// ```swift
  /// let a = 10
  /// let b = 5
  /// print(#stringify(a + b))
  /// ```
  ///
  /// Generated content of reference document url:
  /// URL:
  /// `sourcekit-lsp://swift-macro-expansion/L3C7-L3C23.swift?fromLine=3&fromColumn=8&toLine=3&toColumn=8&bufferName=@__swift_macro_..._Stringify_.swift&parent=/path/to/swift_file.swift`
  /// ```swift
  /// (a + b, "a + b")
  /// ```
  ///
  /// Here the `bufferName` of the reference document url is `@__swift_macro_..._Stringify_.swift`
  package var bufferName: String

  /// The range at which the expanded macro should be inserted. For freestanding macros, this will be the full range of
  /// the macro expansion expr/decl.
  /// For attached macros, this is the position at which the buffer should be inserted, which could be at a different
  /// location than the macro attribute (eg. attached member macros).
  package var macroExpansionEditRange: Range<Position>

  package init(
    macroExpansionEditRange: Range<Position>,
    parent: DocumentURI,
    parentSelectionRange: Range<Position>,
    bufferName: String
  ) {
    self.macroExpansionEditRange = macroExpansionEditRange
    self.parent = parent
    self.parentSelectionRange = parentSelectionRange
    self.bufferName = bufferName
  }

  package var displayName: String {
    "L\(macroExpansionEditRange.lowerBound.line + 1)C\(macroExpansionEditRange.lowerBound.utf16index + 1)-L\(macroExpansionEditRange.upperBound.line + 1)C\(macroExpansionEditRange.upperBound.utf16index + 1).swift"
  }

  package var queryItems: [URLQueryItem] {
    [
      URLQueryItem(name: Parameters.fromLine, value: String(parentSelectionRange.lowerBound.line)),
      URLQueryItem(name: Parameters.fromColumn, value: String(parentSelectionRange.lowerBound.utf16index)),
      URLQueryItem(name: Parameters.toLine, value: String(parentSelectionRange.upperBound.line)),
      URLQueryItem(name: Parameters.toColumn, value: String(parentSelectionRange.upperBound.utf16index)),
      URLQueryItem(name: Parameters.bufferName, value: bufferName),

      // *Note*: Having `parent` as the last parameter will ensure that the url's parameters aren't mistaken to be its
      // `parent`'s parameters in certain environments where percent encoding gets removed or added
      // unnecessarily (for example: VS Code)
      URLQueryItem(name: Parameters.parent, value: parent.stringValue),
    ]
  }

  package init(displayName: String, queryItems: [URLQueryItem]) throws {
    guard let parent = queryItems.last(where: { $0.name == Parameters.parent })?.value,
      let fromLine = Int(queryItems.last(where: { $0.name == Parameters.fromLine })?.value ?? ""),
      let fromColumn = Int(queryItems.last(where: { $0.name == Parameters.fromColumn })?.value ?? ""),
      let toLine = Int(queryItems.last(where: { $0.name == Parameters.toLine })?.value ?? ""),
      let toColumn = Int(queryItems.last(where: { $0.name == Parameters.toColumn })?.value ?? ""),
      let bufferName = queryItems.last(where: { $0.name == Parameters.bufferName })?.value
    else {
      throw ReferenceDocumentURLError(description: "Invalid queryItems for macro expansion reference document url")
    }

    self.parent = try DocumentURI(string: parent)
    self.parentSelectionRange =
      Position(line: fromLine, utf16index: fromColumn)..<Position(line: toLine, utf16index: toColumn)
    self.bufferName = bufferName
    self.macroExpansionEditRange = try Self.parse(displayName: displayName)
  }

  /// The URI of the document from which this reference document was derived.
  /// This is used to determine the workspace and language service that is used to generate the reference document.
  ///
  /// ## Example
  ///
  /// User's source File:
  /// URL: `file://path/to/swift_file.swift`
  /// ```swift
  /// let a = 10
  /// let b = 5
  /// print(#stringify(a + b))
  /// ```
  ///
  /// Generated content of reference document url:
  /// URL:
  /// `sourcekit-lsp://swift-macro-expansion/L3C7-L3C23.swift?fromLine=3&fromColumn=8&toLine=3&toColumn=8&bufferName=@__swift_macro_..._Stringify_.swift&parent=/path/to/swift_file.swift`
  /// ```swift
  /// (a + b, "a + b")
  /// ```
  ///
  /// Here the `primaryFile` of the reference document url is a `DocumentURI`
  /// with the following url: `file:///path/to/swift_file.swift`
  ///
  /// - Note: In case of nested macro expansion reference documents, they all will have the same `primaryFile`
  ///   as that of the first macro expansion reference document i.e. `primaryFile` doesn't change.
  package var primaryFile: DocumentURI {
    switch try? ReferenceDocumentURL(from: parent) {
    case .macroExpansion(let data):
      data.primaryFile
    case .generatedInterface, nil:
      parent
    }
  }

  package var primaryFileSelectionRange: Range<Position> {
    switch try? ReferenceDocumentURL(from: parent) {
    case .macroExpansion(let data):
      data.primaryFileSelectionRange
    case .generatedInterface, nil:
      self.parentSelectionRange
    }
  }

  private struct Parameters {
    static let parent = "parent"
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
