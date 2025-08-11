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
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import LanguageServerProtocolJSONRPC
import SKLogging
import SKUtilities
import SwiftExtensions
import SwiftParser
import SwiftSyntax
import TSCExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.LocalFileOutputByteStream
import class TSCBasic.Process
import protocol TSCBasic.WritableByteStream

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
    case .insert(let offset, element: _, associatedWith: _):
      return offset
    case .remove(let offset, element: _, associatedWith: _):
      return offset
    }
  }
}

/// Compute the text edits that need to be made to transform `original` into `edited`.
private func edits(from original: DocumentSnapshot, to edited: String) -> [TextEdit] {
  let difference = edited.utf8.difference(from: original.text.utf8)

  let sequentialEdits = difference.map { change in
    switch change {
    case .insert(let offset, let element, associatedWith: _):
      let absolutePosition = AbsolutePosition(utf8Offset: offset)
      return SourceEdit(range: absolutePosition..<absolutePosition, replacement: [element])
    case .remove(let offset, element: _, associatedWith: _):
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
      snapshot: documentManager.latestSnapshot(req.textDocument.uri),
      textDocument: req.textDocument,
      options: req.options
    )
  }

  package func documentRangeFormatting(_ req: DocumentRangeFormattingRequest) async throws -> [TextEdit]? {
    return try await format(
      snapshot: documentManager.latestSnapshot(req.textDocument.uri),
      textDocument: req.textDocument,
      options: req.options,
      range: req.range
    )
  }

  package func documentOnTypeFormatting(_ req: DocumentOnTypeFormattingRequest) async throws -> [TextEdit]? {
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)
    guard let line = snapshot.lineTable.line(at: req.position.line) else {
      return nil
    }

    let lineStartPosition = snapshot.position(of: line.startIndex, fromLine: req.position.line)
    let lineEndPosition = snapshot.position(of: line.endIndex, fromLine: req.position.line)

    return try await format(
      snapshot: snapshot,
      textDocument: req.textDocument,
      options: req.options,
      range: lineStartPosition..<lineEndPosition
    )
  }

  private func format(
    snapshot: DocumentSnapshot,
    textDocument: TextDocumentIdentifier,
    options: FormattingOptions,
    range: Range<Position>? = nil
  ) async throws -> [TextEdit]? {
    guard let swiftFormat else {
      throw ResponseError.unknown(
        "Formatting not supported because the toolchain is missing the swift-format executable"
      )
    }

    var args = try [
      swiftFormat.filePath,
      "format",
      "-",  // Read file contents from stdin
      "--configuration",
      swiftFormatConfiguration(for: textDocument.uri, options: options),
    ]
    if let range {
      let utf8Range = snapshot.utf8OffsetRange(of: range)
      // swift-format takes an inclusive range, but Swift's `Range.upperBound` is exclusive.
      // Also make sure `upperBound` does not go less than `lowerBound`.
      let utf8UpperBound = max(utf8Range.lowerBound, utf8Range.upperBound - 1)
      args += [
        "--offsets",
        "\(utf8Range.lowerBound):\(utf8UpperBound)",
      ]
    }
    let process = TSCBasic.Process(arguments: args)
    let writeStream: any WritableByteStream
    do {
      writeStream = try process.launch()
    } catch {
      throw ResponseError.unknown("Launching swift-format failed: \(error)")
    }
    #if canImport(Darwin)
    // On Darwin, we can disable SIGPIPE for a single pipe. This is not available on all platforms, in which case we
    // resort to disabling SIGPIPE globally to avoid crashing SourceKit-LSP with SIGPIPE if swift-format crashes before
    // we could send all data to its stdin.
    if let byteStream = writeStream as? LocalFileOutputByteStream {
      orLog("Disable SIGPIPE for swift-format stdin") {
        try byteStream.disableSigpipe()
      }
    } else {
      logger.fault("Expected write stream to process to be a LocalFileOutputByteStream")
    }
    #else
    globallyDisableSigpipeIfNeeded()
    #endif

    do {
      // Send the file to format to swift-format's stdin. That way we don't have to write it to a file.
      //
      // If we are on Windows, `writeStream` is not a swift-tools-support-core type but a `FileHandle`. In that case,
      // call the throwing `write(contentsOf:)` method on it so that we can catch a `ERROR_BROKEN_PIPE` error. The
      // `send` method that we use on all other platforms ends up calling the non-throwing `FileHandle.write(_:)`, which
      // calls `write(contentsOf:)` using `try!` and thus crashes SourceKit-LSP if the pipe to swift-format is closed,
      // eg. because swift-format has crashed.
      if let fileHandle = writeStream as? FileHandle {
        try fileHandle.write(contentsOf: Data(snapshot.text.utf8))
      } else {
        writeStream.send(snapshot.text.utf8)
      }
      try writeStream.close()
    } catch {
      throw ResponseError.unknown("Writing to swift-format stdin failed: \(error)")
    }

    let result = try await withTimeout(.seconds(60)) {
      try await process.waitUntilExitStoppingProcessOnTaskCancellation()
    }
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
