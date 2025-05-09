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

package import Foundation
import RegexBuilder
import SwiftExtensions

/// All the information necessary to replay a sourcektid request.
package struct RequestInfo: Sendable {
  /// The JSON request object. Contains the following dynamic placeholders:
  ///  - `$COMPILER_ARGS`: Will be replaced by the compiler arguments of the request
  ///  - `$FILE`: Will be replaced with a path to the file that contains the reduced source code.
  ///  - `$FILE_CONTENTS`: Will be replaced by the contents of the reduced source file inside quotes
  ///  - `$OFFSET`: To be replaced by `offset` before running the request
  var requestTemplate: String

  /// Requests that should be executed before `requestTemplate` to set up state in sourcekitd so that `requestTemplate`
  /// can reproduce an issue, eg. sending an `editor.open` before a `codecomplete.open` so that we have registered the
  /// compiler arguments in the SourceKit plugin.
  ///
  /// These request templates receive the same substitutions as `requestTemplate`.
  var contextualRequestTemplates: [String]

  /// The offset at which the sourcekitd request should be run. Replaces the
  /// `$OFFSET` placeholder in the request template.
  var offset: Int

  /// The compiler arguments of the request. Replaces the `$COMPILER_ARGS`placeholder in the request template.
  package var compilerArgs: [String]

  /// The contents of the file that the sourcekitd request operates on.
  package var fileContents: String

  package func requests(for file: URL) throws -> [String] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard var compilerArgs = String(data: try encoder.encode(compilerArgs), encoding: .utf8) else {
      throw GenericError("Failed to encode compiler arguments")
    }
    // Drop the opening `[` and `]`. The request template already contains them
    compilerArgs = String(compilerArgs.dropFirst().dropLast())
    let quotedFileContents =
      try String(data: JSONEncoder().encode(try String(contentsOf: file, encoding: .utf8)), encoding: .utf8) ?? ""
    return try (contextualRequestTemplates + [requestTemplate]).map { requestTemplate in
      requestTemplate
        .replacingOccurrences(of: "$OFFSET", with: String(offset))
        .replacingOccurrences(of: "$COMPILER_ARGS", with: compilerArgs)
        .replacingOccurrences(of: "$FILE_CONTENTS", with: quotedFileContents)
        .replacingOccurrences(of: "$FILE", with: try file.filePath.replacing(#"\"#, with: #"\\"#))
    }
  }

  /// A fake value that is used to indicate that we are reducing a `swift-frontend` issue instead of a sourcekitd issue.
  static let fakeRequestTemplateForFrontendIssues = """
    {
      key.request: sourcekit-lsp-fake-request-for-frontend-crash
      key.compilerargs: [
        $COMPILER_ARGS
      ]
    }
    """

  package init(
    requestTemplate: String,
    contextualRequestTemplates: [String],
    offset: Int,
    compilerArgs: [String],
    fileContents: String
  ) {
    self.requestTemplate = requestTemplate
    self.contextualRequestTemplates = contextualRequestTemplates
    self.offset = offset
    self.compilerArgs = compilerArgs
    self.fileContents = fileContents
  }

  /// Creates `RequestInfo` from the contents of the JSON sourcekitd request at `requestPath`.
  ///
  /// The contents of the source file are read from disk.
  package init(request: String) throws {
    var requestTemplate = request

    // If the request contained source text, remove it. We want to pick it up from the file on disk and most (possibly
    // all) sourcekitd requests use key.sourcefile if key.sourcetext is missing.
    requestTemplate.replace(#/ *key.sourcetext: .*\n/#, with: #"key.sourcetext: $FILE_CONTENTS\#n"#)

    let sourceFilePath: URL
    (requestTemplate, offset) = try extractOffset(from: requestTemplate)
    (requestTemplate, sourceFilePath) = try extractSourceFile(from: requestTemplate)
    (requestTemplate, compilerArgs) = try extractCompilerArguments(from: requestTemplate)

    self.requestTemplate = requestTemplate
    self.contextualRequestTemplates = []

    fileContents = try String(contentsOf: sourceFilePath, encoding: .utf8)
  }

  /// Create a `RequestInfo` that is used to reduce a `swift-frontend issue`
  init(frontendArgs: [String]) throws {
    var frontendArgsWithFilelistInlined: [String] = []

    var iterator = frontendArgs.makeIterator()

    // Inline the file list so we can reduce the compiler arguments by removing individual source files.
    // A couple `output-filelist`-related compiler arguments don't work with the file list inlined. Remove them as they
    // are unlikely to be responsible for the swift-frontend cache.
    // `-index-system-modules` is invalid when no output file lists are specified.
    while let frontendArg = iterator.next() {
      switch frontendArg {
      case "-supplementary-output-file-map", "-output-filelist", "-index-unit-output-path-filelist",
        "-index-system-modules":
        _ = iterator.next()
      case "-filelist":
        guard let fileList = iterator.next() else {
          throw GenericError("Expected file path after -filelist command line argument")
        }
        frontendArgsWithFilelistInlined += try String(contentsOfFile: fileList, encoding: .utf8)
          .split(separator: "\n")
          .map { String($0) }
      default:
        frontendArgsWithFilelistInlined.append(frontendArg)
      }
    }

    // File contents are not known because there are multiple input files. Will usually be set after running
    // `mergeSwiftFiles`.
    self.init(
      requestTemplate: Self.fakeRequestTemplateForFrontendIssues,
      contextualRequestTemplates: [],
      offset: 0,
      compilerArgs: frontendArgsWithFilelistInlined,
      fileContents: ""
    )
  }
}

private func extractOffset(from requestTemplate: String) throws -> (template: String, offset: Int) {
  let offsetRegex = Regex {
    "key.offset: "
    Capture(ZeroOrMore(.digit))
  }
  guard let offsetMatch = requestTemplate.matches(of: offsetRegex).only else {
    return (requestTemplate, 0)
  }
  let requestTemplate = requestTemplate.replacing(offsetRegex, with: "key.offset: $OFFSET")
  return (requestTemplate, Int(offsetMatch.1)!)
}

private func extractSourceFile(from requestTemplate: String) throws -> (template: String, sourceFile: URL) {
  var requestTemplate = requestTemplate
  let sourceFileRegex = Regex {
    #"key.sourcefile: ""#
    Capture(ZeroOrMore(#/[^"]/#))
    "\""
  }
  let nameRegex = Regex {
    #"key.name: ""#
    Capture(ZeroOrMore(#/[^"]/#))
    "\""
  }
  let sourceFileMatch = requestTemplate.matches(of: sourceFileRegex).only
  let nameMatch = requestTemplate.matches(of: nameRegex).only

  let sourceFilePath: String?
  if let sourceFileMatch {
    sourceFilePath = String(sourceFileMatch.1)
    requestTemplate.replace(sourceFileMatch.1, with: "$FILE")
  } else {
    sourceFilePath = nil
  }

  let namePath: String?
  if let nameMatch {
    namePath = String(nameMatch.1)
    requestTemplate.replace(nameMatch.1, with: "$FILE")
  } else {
    namePath = nil
  }
  switch (sourceFilePath, namePath) {
  case (let sourceFilePath?, let namePath?):
    if sourceFilePath != namePath {
      throw GenericError("Mismatching find key.sourcefile and key.name in the request")
    }
    return (requestTemplate, URL(fileURLWithPath: sourceFilePath))
  case (let sourceFilePath?, nil):
    return (requestTemplate, URL(fileURLWithPath: sourceFilePath))
  case (nil, let namePath?):
    return (requestTemplate, URL(fileURLWithPath: namePath))
  case (nil, nil):
    throw GenericError("Failed to find key.sourcefile or key.name in the request")
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
  let compilerArgs = try JSONDecoder().decode([String].self, from: Data(compilerArgsJson.utf8))
  return (template.joined(separator: "\n"), compilerArgs)
}
