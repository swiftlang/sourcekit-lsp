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

#if compiler(>=6)
import Foundation
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SwiftExtensions
import SwiftParser
import SwiftSyntax
import TSCExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import func TSCBasic.withTemporaryFile
#else
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SwiftExtensions
import SwiftParser
import SwiftSyntax
import TSCExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import func TSCBasic.withTemporaryFile
#endif

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
  let difference = edited.utf8.difference(from: original.text.utf8)

  let sequentialEdits = difference.map { change in
    switch change {
    case .insert(offset: let offset, element: let element, associatedWith: _):
      let absolutePosition = AbsolutePosition(utf8Offset: offset)
      return SourceEdit(range: absolutePosition..<absolutePosition, replacement: [element])
    case .remove(offset: let offset, element: _, associatedWith: _):
      let absolutePosition = AbsolutePosition(utf8Offset: offset)
      return SourceEdit(range: absolutePosition..<absolutePosition.advanced(by: 1), replacement: [])
    }
  }

  let concurrentEdits = ConcurrentEdits(fromSequential: sequentialEdits)

  // Map the offset-based edits to line-column based edits to be consumed by LSP

  return concurrentEdits.edits.compactMap {
    TextEdit(range: original.absolutePositionRange(of: $0.range), newText: $0.replacement)
  }
}

extension SwiftLanguageService {
  package func documentFormatting(_ req: DocumentFormattingRequest) async throws -> [TextEdit]? {
    return try await format(
      textDocument: req.textDocument,
      options: req.options
    )
  }

  package func documentRangeFormatting(_ req: DocumentRangeFormattingRequest) async throws -> [TextEdit]? {
    return try await format(
      textDocument: req.textDocument,
      options: req.options,
      range: req.range
    )
  }

  private func format(
    textDocument: TextDocumentIdentifier,
    options: FormattingOptions,
    range: Range<Position>? = nil
  ) async throws -> [TextEdit]? {
    let snapshot = try documentManager.latestSnapshot(textDocument.uri)

    guard let swiftFormat else {
      throw ResponseError.unknown(
        "Formatting not supported because the toolchain is missing the swift-format executable"
      )
    }

    var args = try [
      swiftFormat.filePath,
      "format",
      "--configuration",
      swiftFormatConfiguration(for: textDocument.uri, options: options),
    ]
    if let range {
      args += [
        "--offsets",
        "\(snapshot.utf8Offset(of: range.lowerBound)):\(snapshot.utf8Offset(of: range.upperBound))",
      ]
    }
    let process = TSCBasic.Process(arguments: args)
    let writeStream = try process.launch()

    // Send the file to format to swift-format's stdin. That way we don't have to write it to a file.
    writeStream.send(snapshot.text)
    try writeStream.close()

    let result = try await process.waitUntilExitStoppingProcessOnTaskCancellation()
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
