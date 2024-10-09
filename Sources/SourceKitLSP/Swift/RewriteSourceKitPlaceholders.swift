//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKLogging
@_spi(RawSyntax) import SwiftSyntax

func rewriteSourceKitPlaceholders(in string: String, clientSupportsSnippets: Bool) -> String {
  var result = string
  var index = 1
  while let start = result.range(of: "<#") {
    guard let end = result[start.upperBound...].range(of: "#>") else {
      logger.fault("Invalid placeholder in \(string)")
      return string
    }
    let rawPlaceholder = String(result[start.lowerBound..<end.upperBound])
    guard let displayName = nameForSnippet(rawPlaceholder) else {
      logger.fault("Failed to decode placeholder \(rawPlaceholder) in \(string)")
      return string
    }
    let snippet = clientSupportsSnippets ? "${\(index):\(displayName)}" : ""
    result.replaceSubrange(start.lowerBound..<end.upperBound, with: snippet)
    index += 1
  }
  return result
}

/// Parse a SourceKit placeholder and extract the display name suitable for a
/// LSP snippet.
fileprivate func nameForSnippet(_ text: String) -> String? {
  var text = text
  return text.withSyntaxText {
    guard let data = RawEditorPlaceholderData(syntaxText: $0) else {
      return nil
    }
    return String(syntaxText: data.typeForExpansionText ?? data.displayText)
  }
}
