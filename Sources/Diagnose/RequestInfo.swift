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
import RegexBuilder

/// All the information necessary to replay a sourcektid request.
@_spi(Testing)
public struct RequestInfo {
  /// The JSON request object. Contains the following dynamic placeholders:
  ///  - `$OFFSET`: To be replaced by `offset` before running the request
  ///  - `$FILE`: Will be replaced with a path to the file that contains the reduced source code.
  ///  - `$COMPILER_ARGS`: Will be replaced by the compiler arguments of the request
  var requestTemplate: String

  /// The offset at which the sourcekitd request should be run. Replaces the
  /// `$OFFSET` placeholder in the request template.
  var offset: Int

  /// The compiler arguments of the request. Replaces the `$COMPILER_ARGS`placeholder in the request template.
  @_spi(Testing)
  public var compilerArgs: [String]

  /// The contents of the file that the sourcekitd request operates on.
  @_spi(Testing)
  public var fileContents: String

  func request(for file: URL) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    guard var compilerArgs = String(data: try encoder.encode(compilerArgs), encoding: .utf8) else {
      throw ReductionError("Failed to encode compiler arguments")
    }
    // Drop the opening `[` and `]`. The request template already contains them
    compilerArgs = String(compilerArgs.dropFirst().dropLast())
    return
      requestTemplate
      .replacingOccurrences(of: "$OFFSET", with: String(offset))
      .replacingOccurrences(of: "$COMPILER_ARGS", with: compilerArgs)
      .replacingOccurrences(of: "$FILE", with: file.path)

  }

  @_spi(Testing)
  public init(requestTemplate: String, offset: Int, compilerArgs: [String], fileContents: String) {
    self.requestTemplate = requestTemplate
    self.offset = offset
    self.compilerArgs = compilerArgs
    self.fileContents = fileContents
  }

  /// Creates `RequestInfo` from the contents of the JSON sourcekitd request at `requestPath`.
  ///
  /// The contents of the source file are read from disk.
  @_spi(Testing)
  public init(request: String) throws {
    var requestTemplate = request

    // Extract offset
    let offsetRegex = Regex {
      "key.offset: "
      Capture(ZeroOrMore(.digit))
    }
    if let offsetMatch = requestTemplate.matches(of: offsetRegex).only {
      offset = Int(offsetMatch.1)!
      requestTemplate.replace(offsetRegex, with: "key.offset: $OFFSET")
    } else {
      offset = 0
    }

    // Extract source file
    let sourceFileRegex = Regex {
      #"key.sourcefile: ""#
      Capture(ZeroOrMore(#/[^"]/#))
      "\""
    }
    guard let sourceFileMatch = requestTemplate.matches(of: sourceFileRegex).only else {
      throw ReductionError("Failed to find key.sourcefile in the request")
    }
    let sourceFilePath = String(sourceFileMatch.1)
    requestTemplate.replace(sourceFileMatch.1, with: "$FILE")

    // Extract compiler arguments
    let compilerArgsExtraction = try extractCompilerArguments(from: requestTemplate)
    requestTemplate = compilerArgsExtraction.template
    compilerArgs = compilerArgsExtraction.compilerArgs

    self.requestTemplate = requestTemplate

    fileContents = try String(contentsOf: URL(fileURLWithPath: sourceFilePath))
  }
}

private func extractCompilerArguments(
  from requestTemplate: String
) throws -> (template: String, compilerArgs: [String]) {
  let lines = requestTemplate.components(separatedBy: "\n")
  guard
    let compilerArgsStartIndex = lines.firstIndex(where: { $0.contains("key.compilerargs: [") }),
    let compilerArgsEndIndex = lines[compilerArgsStartIndex...].firstIndex(where: {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("]")
    })
  else {
    return (requestTemplate, [])
  }
  let template = lines[...compilerArgsStartIndex] + ["$COMPILER_ARGS"] + lines[compilerArgsEndIndex...]
  let compilerArgsJson = "[" + lines[(compilerArgsStartIndex + 1)..<compilerArgsEndIndex].joined(separator: "\n") + "]"
  let compilerArgs = try JSONDecoder().decode([String].self, from: compilerArgsJson)
  return (template.joined(separator: "\n"), compilerArgs)
}
