//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import LanguageServerProtocol

extension String {
  /// Returns a new string obtained by applying the given text edits to this
  /// string.
  package func applying(_ edits: [TextEdit]) -> String {
    let sortedEdits = edits.sorted { lhs, rhs in
      lhs.range.lowerBound < rhs.range.lowerBound
    }

    let lines = self.split(separator: /\v/, omittingEmptySubsequences: false)
    var result = ""
    var currentLine = 0
    var currentPos = lines[0].startIndex

    Edits: for edit in sortedEdits {
      // Copy any unchanged lines into the result
      while currentLine < edit.range.lowerBound.line {
        result.append(String(lines[currentLine][currentPos...]))
        result.append("\n")
        currentLine += 1
        if currentLine == lines.count { break Edits }
        currentPos = lines[currentLine].startIndex
      }

      // Copy any prefix in this line into the result
      let editStart = lines[currentLine].utf16
        .index(lines[currentLine].startIndex, offsetBy: edit.range.lowerBound.utf16index)
      let prefixRange = currentPos..<editStart
      let prefix = lines[currentLine][prefixRange]
      result += prefix

      // Add the new text (if any)
      result += edit.newText

      // Prepare the next cursor position
      currentLine = edit.range.upperBound.line
      currentPos = lines[currentLine].utf16
        .index(lines[currentLine].startIndex, offsetBy: edit.range.upperBound.utf16index)
    }

    // Copy any remainder
    while currentLine < lines.count {
      result.append(String(lines[currentLine][currentPos...]))
      result.append("\n")
      currentLine += 1
      if currentLine == lines.count { break }
      currentPos = lines[currentLine].startIndex
    }

    return result
  }
}
