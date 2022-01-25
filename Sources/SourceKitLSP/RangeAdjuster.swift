//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

/// Given an edit event, the `RangeAdjuster` can adjust ranges in the pre-edit
/// document to the corresponding ranges in the post-edit document
struct RangeAdjuster {
  /// The edit that ranges should be adjusted for
  let editRange: Range<Position>

  /// Number of lines that ranges after the `editRange` should be moved down (or up if negative).
  let lineDelta: Int

  /// Number of UTF-16 indicies that ranges, which are on the last line of `editRange` but after the UTF-16 column of `editRange` should be shifted to the right (or left if negative).
  let lastLineCharDelta: Int

  init?(edit: TextDocumentContentChangeEvent) {
    guard let editRange = edit.range else {
      return nil
    }
    self.editRange = editRange

    let replacedLineCount = 1 + editRange.upperBound.line - editRange.lowerBound.line
    let newLines = edit.text.split(separator: "\n", omittingEmptySubsequences: false)
    let upperUtf16IndexAfterEdit = (
      newLines.count == 1 ? editRange.lowerBound.utf16index : 0
    ) + newLines.last!.utf16.count
    self.lastLineCharDelta = upperUtf16IndexAfterEdit - editRange.upperBound.utf16index
    self.lineDelta = newLines.count - replacedLineCount // may be negative
  }

  /// Adjust the pre-edit `range` to the corresponding range in the post-edit document.
  /// If the range overlaps with the edit, returns `nil`.
  func adjust(_ range: Range<Position>) -> Range<Position>? {
    if range.overlaps(editRange) {
      return nil
    }
    let lineOffset: Int
    let charOffset: Int
    if range.lowerBound.line == editRange.upperBound.line,
       range.lowerBound.utf16index >= editRange.upperBound.utf16index {
      lineOffset = lineDelta
      charOffset = lastLineCharDelta
    } else if range.lowerBound.line > editRange.upperBound.line {
      lineOffset = lineDelta
      charOffset = 0
    } else {
      lineOffset = 0
      charOffset = 0
    }
    let newStart = Position(line: range.lowerBound.line + lineOffset, utf16index: range.lowerBound.utf16index + charOffset)
    let newEnd = Position(line: range.upperBound.line + lineOffset, utf16index: range.upperBound.utf16index + charOffset)
    return newStart..<newEnd
  }
}
