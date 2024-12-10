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

import Foundation
import SKLogging
@_spi(RawSyntax) import SwiftSyntax

/// Translate SourceKit placeholder syntax — `<#foo#>` — in `input` to LSP
/// placeholder syntax: `${n:foo}`.
///
/// If `clientSupportsSnippets` is `false`, the placeholder is rendered as an
/// empty string, to prevent the client from inserting special placeholder
/// characters as if they were literal text.
@_spi(Testing)
public func rewriteSourceKitPlaceholders(in input: String, clientSupportsSnippets: Bool) -> String {
  var result = ""
  var nextPlaceholderNumber = 1
  // Current stack of nested placeholders, most nested last. Each element needs
  // to be rendered inside the element before it.
  var placeholders: [(number: Int, contents: String)] = []
  let tokens = tokenize(input)
  for token in tokens {
    switch token {
    case let .text(text):
      if placeholders.isEmpty {
        result += text
      } else {
        placeholders.latest.contents += text
      }

    case .escapeInsidePlaceholder(let character):
      if placeholders.isEmpty {
        result.append(character)
      } else {
        // A closing brace is only escaped _inside_ a placeholder; otherwise the client would include the backslashes
        // literally.
        placeholders.latest.contents += [#"\"#, character]
      }

    case .placeholderOpen:
      placeholders.append((number: nextPlaceholderNumber, contents: ""))
      nextPlaceholderNumber += 1

    case .placeholderClose:
      guard let (number, placeholderBody) = placeholders.popLast() else {
        logger.fault("Invalid placeholder in \(input)")
        return input
      }
      guard let displayName = nameForSnippet(placeholderBody) else {
        logger.fault("Failed to decode placeholder \(placeholderBody) in \(input)")
        return input
      }
      let placeholder =
        clientSupportsSnippets
        ? formatLSPPlaceholder(displayName, number: number)
        : ""
      if placeholders.isEmpty {
        result += placeholder
      } else {
        placeholders.latest.contents += placeholder
      }
    }
  }

  return result
}

/// Scan `input` to identify special elements within: curly braces, which may
/// need to be escaped; and SourceKit placeholder open/close delimiters.
private func tokenize(_ input: String) -> [SnippetToken] {
  var index = input.startIndex
  var isAtEnd: Bool { index == input.endIndex }
  func match(_ char: Character) -> Bool {
    if isAtEnd || input[index] != char {
      return false
    } else {
      input.formIndex(after: &index)
      return true
    }
  }
  func next() -> Character? {
    guard !isAtEnd else { return nil }
    defer { input.formIndex(after: &index) }
    return input[index]
  }

  var tokens: [SnippetToken] = []
  var text = ""
  while let char = next() {
    switch char {
    case "<":
      if match("#") {
        tokens.append(.text(text))
        text.removeAll()
        tokens.append(.placeholderOpen)
      } else {
        text.append(char)
      }

    case "#":
      if match(">") {
        tokens.append(.text(text))
        text.removeAll()
        tokens.append(.placeholderClose)
      } else {
        text.append(char)
      }

    case "$", "}", "\\":
      tokens.append(.text(text))
      text.removeAll()
      tokens.append(.escapeInsidePlaceholder(char))

    case let c:
      text.append(c)
    }
  }

  tokens.append(.text(text))

  return tokens
}

/// A syntactical element inside a SourceKit snippet.
private enum SnippetToken {
  /// A placeholder delimiter.
  case placeholderOpen, placeholderClose
  /// '$', '}' or '\', which need to be escaped when used inside a placeholder.
  case escapeInsidePlaceholder(Character)
  /// Any other consecutive run of characters from the input, which needs no
  /// special treatment.
  case text(String)
}

/// Given the interior text of a SourceKit placeholder, extract a display name
/// suitable for a LSP snippet.
private func nameForSnippet(_ body: String) -> String? {
  var text = rewrappedAsPlaceholder(body)
  return text.withSyntaxText {
    guard let data = RawEditorPlaceholderData(syntaxText: $0) else {
      return nil
    }
    return String(syntaxText: data.typeForExpansionText ?? data.displayText)
  }
}

private let placeholderStart = "<#"
private let placeholderEnd = "#>"
private func rewrappedAsPlaceholder(_ body: String) -> String {
  return placeholderStart + body + placeholderEnd
}

/// Wrap `body` in LSP snippet placeholder syntax, using `number` as the
/// placeholder's index in the snippet.
private func formatLSPPlaceholder(_ body: String, number: Int) -> String {
  "${\(number):\(body)}"
}

private extension Array {
  /// Mutable access to the final element of an array.
  ///
  /// - precondition: The array must not be empty.
  var latest: Element {
    get { self.last! }
    _modify {
      let index = self.index(before: self.endIndex)
      yield &self[index]
    }
  }
}
