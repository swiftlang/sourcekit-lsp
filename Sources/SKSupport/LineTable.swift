//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct LineTable: Hashable {
  @usableFromInline
  var impl: [String.Index]

  public var content: String

  public init(_ string: String) {
    content = string

    var i = string.startIndex
    impl = [i]
    while i != string.endIndex {
      let c = string[i]
      string.formIndex(after: &i)
      if c == "\n" || c == "\r\n" || c == "\r" {
        impl.append(i)
      }
    }
  }

  /// The number of lines.
  @inlinable
  public var count: Int { return impl.count }

  /// Returns the given (zero-based) line as a Substring, including the newline.
  ///
  /// - parameter line: Line number (zero-based).
  @inlinable
  public subscript(line: Int) -> Substring {
    return content[impl[line] ..< (line == count - 1 ? content.endIndex : impl[line + 1])]
  }

  /// Translate String.Index to logical line/utf16 pair.
  @usableFromInline
  func lineAndUTF16ColumnOf(_ index: String.Index, fromLine: Int = 0) -> (line: Int, utf16Column: Int) {
    precondition(0 <= fromLine && fromLine < count)

    // Binary search.
    var lower = fromLine
    var upper = count
    while true {
      let mid = lower + (upper - lower) / 2
      let lineStartIndex = impl[mid]
      if mid == lower || lineStartIndex == index {
        return (
          line: mid,
          utf16Column: content.utf16.distance(from: lineStartIndex, to: index)
        )
      } else if lineStartIndex < index {
        lower = mid
      } else {
        upper = mid
      }
    }
  }
}

extension LineTable: RandomAccessCollection {
  public var startIndex: Int {
    return impl.startIndex
  }

  public var endIndex: Int {
    return impl.endIndex
  }
}

extension LineTable {

  // MARK: - Editing

  /// Replace the line table's `content` in the given range and update the line data.
  ///
  /// - parameter fromLine: Starting line number (zero-based).
  /// - parameter fromOff: Starting UTF-16 column offset (zero-based).
  /// - parameter toLine: Ending line number (zero-based).
  /// - parameter toOff: Ending UTF-16 column offset (zero-based).
  /// - parameter replacement: The new text for the given range.
  @inlinable
  mutating public func replace(
    fromLine: Int,
    utf16Offset fromOff: Int,
    toLine: Int,
    utf16Offset toOff: Int,
    with replacement: String)
  {
    let start = content.utf16.index(impl[fromLine], offsetBy: fromOff)
    let end = content.utf16.index(impl[toLine], offsetBy: toOff)

    var newText = self.content
    newText.replaceSubrange(start..<end, with: replacement)

    self = LineTable(newText)
  }

  /// Edit the line table's `content` and update the line data.
  ///
  /// - parameter fromLine: Starting line number (zero-based).
  /// - parameter fromOff: Starting UTF-16 column offset (zero-based).
  /// - parameter utf16Length: The number of UTF-16 code units to replace.
  /// - parameter replacement: The new text for the given range.
  mutating public func replace(
    fromLine: Int,
    utf16Offset fromOff: Int,
    utf16Length: Int,
    with replacement: String)
  {
    let start = content.utf16.index(impl[fromLine], offsetBy: fromOff)
    let end = content.utf16.index(start, offsetBy: utf16Length)
    let (toLine, toOff) = lineAndUTF16ColumnOf(end, fromLine: fromLine)
    self.replace(fromLine: fromLine, utf16Offset: fromOff, toLine: toLine, utf16Offset: toOff, with: replacement)
  }
}

extension LineTable {

  // MARK: - Position translation

  /// Returns `String.Index` of given logical position.
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf16Column: UTF-16 column offset (zero-based).
  @inlinable
  public func stringIndexOf(line: Int, utf16Column: Int) -> String.Index? {
    guard line < count else {
      // Line out of range.
      return nil
    }
    let lineSlice = self[line]
    return content.utf16.index(lineSlice.startIndex, offsetBy: utf16Column, limitedBy: lineSlice.endIndex)
  }

  /// Returns UTF8 buffer offset of given logical position.
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf16Column: UTF-16 column offset (zero-based).
  @inlinable
  public func utf8OffsetOf(line: Int, utf16Column: Int) -> Int? {
    guard let stringIndex = stringIndexOf(line: line, utf16Column: utf16Column) else {
      return nil
    }
    return content.utf8.distance(from: content.startIndex, to: stringIndex)
  }

  /// Returns logical position of given source offset.
  ///
  /// - parameter utf8Offset: UTF-8 buffer offset (zero-based).
  @inlinable
  public func lineAndUTF16ColumnOf(utf8Offset: Int) -> (line: Int, utf16Column: Int)? {
    guard utf8Offset <= content.utf8.count else {
      // Offset ouf of range.
      return nil
    }
    return lineAndUTF16ColumnOf(content.utf8.index(content.startIndex, offsetBy: utf8Offset))
  }

  /// Returns UTF16 column offset at UTF8 version of logical position.
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf8Column: UTF-8 column offset (zero-based).
  @inlinable
  public func utf16ColumnAt(line: Int, utf8Column: Int) -> Int? {
    return convertColumn(
      line: line,
      column: utf8Column,
      indexFunction: content.utf8.index(_:offsetBy:limitedBy:),
      distanceFunction: content.utf16.distance(from:to:))
  }

  /// Returns UTF8 column offset at UTF16 version of logical position.
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf16Column: UTF-16 column offset (zero-based).
  @inlinable
  public func utf8ColumnAt(line: Int, utf16Column: Int) -> Int? {
    return convertColumn(
      line: line,
      column: utf16Column,
      indexFunction: content.utf16.index(_:offsetBy:limitedBy:),
      distanceFunction: content.utf8.distance(from:to:))
  }

  @inlinable
  func convertColumn(line: Int, column: Int, indexFunction: (Substring.Index, Int, Substring.Index) -> Substring.Index?, distanceFunction: (Substring.Index, Substring.Index) -> Int) -> Int? {
    guard line < count else {
      // Line out of range.
      return nil
    }
    let lineSlice = self[line]
    guard let targetIndex = indexFunction(lineSlice.startIndex, column, lineSlice.endIndex) else {
      // Column out of range
      return nil
    }
    return distanceFunction(lineSlice.startIndex, targetIndex)
  }
}
