//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import func TSCBasic.withTemporaryFile

fileprivate extension String {
  init?(bytes: [UInt8], encoding: Encoding) {
    let data = bytes.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return Data()
      }
      return Data(bytes: baseAddress, count: buffer.count)
    }
    self.init(data: data, encoding: encoding)
  }
}

/// If a parent directory of `fileURI` contains a `.swift-format` file, return the path to that file.
/// Otherwise, return `nil`.
private func swiftFormatFile(for fileURI: DocumentURI) -> AbsolutePath? {
  guard var path = try? AbsolutePath(validating: fileURI.pseudoPath) else {
    return nil
  }
  repeat {
    path = path.parentDirectory
    let configFile = path.appending(component: ".swift-format")
    if FileManager.default.isReadableFile(atPath: configFile.pathString) {
      return configFile
    }
  } while !path.isRoot
  return nil
}

/// If a `.swift-format` file is discovered that applies to `fileURI`, return the path to that file.
/// Otherwise, return a JSON object containing the configuration parameters from `options`.
///
/// The result of this function can be passed to the `--configuration` parameter of swift-format.
private func swiftFormatConfiguration(
  for fileURI: DocumentURI,
  options: FormattingOptions
) throws -> String {
  if let configFile = swiftFormatFile(for: fileURI) {
    // If we find a .swift-format file, we ignore the options passed to us by the editor.
    // Most likely, the editor inferred them from the current document and thus the options
    // passed by the editor are most likely less correct than those in .swift-format.
    return configFile.pathString
  }

  // The following options are not supported by swift-format and ignored:
  // - trimTrailingWhitespace: swift-format always trims trailing whitespace
  // - insertFinalNewline: swift-format always inserts a final newline to the file
  // - trimFinalNewlines: swift-format always trims final newlines

  if options.insertSpaces {
    return """
      {
        "version": 1,
        "tabWidth": \(options.tabSize),
        "indentation": { "spaces": \(options.tabSize) }
      }
      """
  } else {
    return """
      {
        "version": 1,
        "tabWidth": \(options.tabSize),
        "indentation": { "tabs": 1 }
      }
      """
  }
}

extension CollectionDifference.Change {
  var offset: Int {
    switch self {
    case .insert(offset: let offset, element: _, associatedWith: _):
      return offset
    case .remove(offset: let offset, element: _, associatedWith: _):
      return offset
    }
  }
}

/// Compute the text edits that need to be made to transform `original` into `edited`.
private func edits(from original: DocumentSnapshot, to edited: String) -> [TextEdit] {
  let difference = edited.difference(from: original.text)

  // `Collection.difference` returns sequential edits that are expected to be applied on-by-one. Offsets reference
  // the string that results if all previous edits are applied.
  // LSP expects concurrent edits that are applied simultaneously. Translate between them.

  struct StringBasedEdit {
    /// Offset into the collection originalString.
    /// Ie. to get a string index out of this, run `original(original.startIndex, offsetBy: range.lowerBound)`.
    var range: Range<Int>
    /// The string the range is being replaced with.
    var replacement: String
  }

  var edits: [StringBasedEdit] = []
  for change in difference {
    // Adjust the index offset based on changes that `Collection.difference` expects to already have been applied.
    var adjustment: Int = 0
    for edit in edits {
      if edit.range.upperBound < change.offset + adjustment {
        adjustment = adjustment + edit.range.count - edit.replacement.count
      }
    }
    let adjustedOffset = change.offset + adjustment
    let edit =
      switch change {
      case .insert(offset: _, element: let element, associatedWith: _):
        StringBasedEdit(range: adjustedOffset..<adjustedOffset, replacement: String(element))
      case .remove(offset: _, element: _, associatedWith: _):
        StringBasedEdit(range: adjustedOffset..<(adjustedOffset + 1), replacement: "")
      }

    // If we have an existing edit that is adjacent to this one, merge them.
    // Otherwise, just append them.
    if let mergableEditIndex = edits.firstIndex(where: {
      $0.range.upperBound == edit.range.lowerBound || edit.range.upperBound == $0.range.lowerBound
    }) {
      let mergableEdit = edits[mergableEditIndex]
      if mergableEdit.range.upperBound == edit.range.lowerBound {
        edits[mergableEditIndex] = StringBasedEdit(
          range: mergableEdit.range.lowerBound..<edit.range.upperBound,
          replacement: mergableEdit.replacement + edit.replacement
        )
      } else {
        precondition(edit.range.upperBound == mergableEdit.range.lowerBound)
        edits[mergableEditIndex] = StringBasedEdit(
          range: edit.range.lowerBound..<mergableEdit.range.upperBound,
          replacement: edit.replacement + mergableEdit.replacement
        )
      }
    } else {
      edits.append(edit)
    }
  }

  // Map the string-based edits to line-column based edits to be consumed by LSP

  return edits.map { edit in
    let (startLine, startColumn) = original.lineTable.lineAndUTF16ColumnOf(
      original.text.index(original.text.startIndex, offsetBy: edit.range.lowerBound)
    )
    let (endLine, endColumn) = original.lineTable.lineAndUTF16ColumnOf(
      original.text.index(original.text.startIndex, offsetBy: edit.range.upperBound)
    )

    return TextEdit(
      range: Position(line: startLine, utf16index: startColumn)..<Position(line: endLine, utf16index: endColumn),
      newText: edit.replacement
    )
  }
}

extension SwiftLanguageServer {
  public func documentFormatting(_ req: DocumentFormattingRequest) async throws -> [TextEdit]? {
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)

    guard let swiftFormat else {
      throw ResponseError.unknown(
        "Formatting not supported because the toolchain is missing the swift-format executable"
      )
    }

    let process = TSCBasic.Process(
      args: swiftFormat.pathString,
      "format",
      "--configuration",
      try swiftFormatConfiguration(for: req.textDocument.uri, options: req.options)
    )
    let writeStream = try process.launch()

    // Send the file to format to swift-format's stdin. That way we don't have to write it to a file.
    writeStream.send(snapshot.text)
    try writeStream.close()

    let result = try await process.waitUntilExit()
    guard result.exitStatus == .terminated(code: 0) else {
      let swiftFormatErrorMessage: String
      switch result.stderrOutput {
      case .success(let stderrBytes):
        swiftFormatErrorMessage = String(bytes: stderrBytes, encoding: .utf8) ?? "unknown error"
      case .failure(let error):
        swiftFormatErrorMessage = String(describing: error)
      }
      throw ResponseError.unknown(
        """
        Running swift-format failed
        \(swiftFormatErrorMessage)
        """
      )
    }
    let formattedBytes: [UInt8]
    switch result.output {
    case .success(let bytes):
      formattedBytes = bytes
    case .failure(let error):
      throw error
    }

    guard let formattedString = String(bytes: formattedBytes, encoding: .utf8) else {
      throw ResponseError.unknown("Failed to decode response from swift-format as UTF-8")
    }

    return edits(from: snapshot, to: formattedString)
  }
}
