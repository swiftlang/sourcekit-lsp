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

import LSPLogging
#if canImport(os)
import os
#endif

public struct LineTable: Hashable, Sendable {
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
    return content[impl[line]..<(line == count - 1 ? content.endIndex : impl[line + 1])]
  }

  /// Translate String.Index to logical line/utf16 pair.
  public func lineAndUTF16ColumnOf(_ index: String.Index, fromLine: Int = 0) -> (line: Int, utf16Column: Int) {
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
    with replacement: String
  ) {
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
    with replacement: String
  ) {
    let start = content.utf16.index(impl[fromLine], offsetBy: fromOff)
    let end = content.utf16.index(start, offsetBy: utf16Length)
    let (toLine, toOff) = lineAndUTF16ColumnOf(end, fromLine: fromLine)
    self.replace(fromLine: fromLine, utf16Offset: fromOff, toLine: toLine, utf16Offset: toOff, with: replacement)
  }
}

// MARK: - Position conversion

extension LineTable {
  // MARK: line:column <-> String.Index

  /// Result of `lineSlice(at:)`
  @usableFromInline
  enum LineSliceResult {
    /// The line index passed to `lineSlice(at:)` was negative.
    case beforeFirstLine
    /// The contents of the line at the index passed to `lineSlice(at:)`.
    case line(Substring)
    /// The line index passed to `lineSlice(at:)` was after the last line of the file
    case afterLastLine
  }

  /// Extracts the contents of the line at the given index.
  ///
  /// If `line` is out-of-bounds, logs a fault and returns either `beforeFirstLine` or `afterLastLine`.
  @usableFromInline
  func lineSlice(at line: Int, callerFile: StaticString, callerLine: UInt) -> LineSliceResult {
    guard line >= 0 else {
      logger.fault(
        """
        Line \(line) is negative (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return .beforeFirstLine
    }
    guard line < count else {
      logger.fault(
        """
        Line \(line) is out-of range (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return .afterLastLine
    }
    return .line(self[line])
  }

  /// Converts the given UTF-16-based `line:column`` position to a `String.Index`.
  ///
  /// If the position does not refer to a valid position with in the source file, returns the closest valid position and
  /// logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf16Column: UTF-16 column offset (zero-based).
  @inlinable
  public func stringIndexOf(
    line: Int,
    utf16Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> String.Index {
    let lineSlice: Substring
    switch self.lineSlice(at: line, callerFile: callerFile, callerLine: callerLine) {
    case .beforeFirstLine:
      return self.content.startIndex
    case .afterLastLine:
      return self.content.endIndex
    case .line(let line):
      lineSlice = line
    }
    guard utf16Column >= 0 else {
      logger.fault(
        """
        Column is negative while converting \(line):\(utf16Column) (UTF-16) to String.Index \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return lineSlice.startIndex
    }
    guard let index = content.utf16.index(lineSlice.startIndex, offsetBy: utf16Column, limitedBy: lineSlice.endIndex)
    else {
      logger.fault(
        """
        Column is past line end while converting \(line):\(utf16Column) (UTF-16) to String.Index \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return lineSlice.endIndex
    }
    return index
  }

  /// Converts the given UTF-8-based `line:column`` position to a `String.Index`.
  ///
  /// If the position does not refer to a valid position with in the source file, returns the closest valid position and
  /// logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf8Column: UTF-8 column offset (zero-based).
  @inlinable
  public func stringIndexOf(
    line: Int,
    utf8Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> String.Index {
    let lineSlice: Substring
    switch self.lineSlice(at: line, callerFile: callerFile, callerLine: callerLine) {
    case .beforeFirstLine:
      return self.content.startIndex
    case .afterLastLine:
      return self.content.endIndex
    case .line(let line):
      lineSlice = line
    }

    guard utf8Column >= 0 else {
      logger.fault(
        """
        Column is negative while converting \(line):\(utf8Column) (UTF-8) to String.Index. \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return lineSlice.startIndex
    }
    guard let index = content.utf8.index(lineSlice.startIndex, offsetBy: utf8Column, limitedBy: lineSlice.endIndex)
    else {
      logger.fault(
        """
        Column is after end of line while converting \(line):\(utf8Column) (UTF-8) to String.Index. \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return lineSlice.endIndex
    }

    return index
  }

  // MARK: line:column <-> UTF-8 offset

  /// Converts the given UTF-16-based `line:column`` position to a UTF-8 offset within the source file.
  ///
  /// If the position does not refer to a valid position with in the source file, returns the closest valid offset and
  /// logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf16Column: UTF-16 column offset (zero-based).
  @inlinable
  public func utf8OffsetOf(
    line: Int,
    utf16Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Int {
    let stringIndex = stringIndexOf(
      line: line,
      utf16Column: utf16Column,
      callerFile: callerFile,
      callerLine: callerLine
    )
    return content.utf8.distance(from: content.startIndex, to: stringIndex)
  }

  /// Converts the given UTF-8-based `line:column` position to a UTF-8 offset within the source file.
  ///
  /// If the position does not refer to a valid position with in the source file, returns the closest valid offset and
  /// logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf8Column: UTF-8 column offset (zero-based).
  @inlinable
  public func utf8OffsetOf(
    line: Int,
    utf8Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Int {
    let stringIndex = stringIndexOf(
      line: line,
      utf8Column: utf8Column,
      callerFile: callerFile,
      callerLine: callerLine
    )
    return content.utf8.distance(from: content.startIndex, to: stringIndex)
  }

  /// Converts the given UTF-8 offset to a zero-based UTF-16 line:column pair.
  ///
  /// If the position does not refer to a valid position with in the snapshot, returns the closest valid line:column
  /// pair and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter utf8Offset: UTF-8 buffer offset (zero-based).
  @inlinable
  public func lineAndUTF16ColumnOf(
    utf8Offset: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> (line: Int, utf16Column: Int) {
    guard utf8Offset >= 0 else {
      logger.fault(
        """
        UTF-8 offset \(utf8Offset) is negative while converting it to UTF-16 line:column \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return (line: 0, utf16Column: 0)
    }
    guard utf8Offset <= content.utf8.count else {
      logger.fault(
        """
        UTF-8 offset \(utf8Offset) is past the end of the file while converting it to UTF-16 line:column \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return lineAndUTF16ColumnOf(content.endIndex)
    }
    return lineAndUTF16ColumnOf(content.utf8.index(content.startIndex, offsetBy: utf8Offset))
  }

  /// Converts the given UTF-8-based line:column position to the UTF-8 offset of that position within the source file.
  ///
  /// If the position does not refer to a valid position with in the snapshot, returns the closest valid line:colum pair
  /// and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  @inlinable func lineAndUTF8ColumnOf(
    utf8Offset: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> (line: Int, utf8Column: Int) {
    let (line, utf16Column) = lineAndUTF16ColumnOf(
      utf8Offset: utf8Offset,
      callerFile: callerFile,
      callerLine: callerLine
    )
    let utf8Column = utf8ColumnAt(
      line: line,
      utf16Column: utf16Column,
      callerFile: callerFile,
      callerLine: callerLine
    )
    return (line, utf8Column)
  }

  // MARK: UTF-8 line:column <-> UTF-16 line:column

  /// Returns UTF-16 column offset at UTF-8 based `line:column` position.
  ///
  /// If the position does not refer to a valid position with in the snapshot, performs a best-effort recovery and logs
  /// a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf8Column: UTF-8 column offset (zero-based).
  @inlinable
  public func utf16ColumnAt(
    line: Int,
    utf8Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Int {
    let lineSlice: Substring
    switch self.lineSlice(at: line, callerFile: callerFile, callerLine: callerLine) {
    case .beforeFirstLine, .afterLastLine:
      // This line is out-of-bounds. `lineSlice(at:)` already logged a fault.
      // Recovery by assuming that UTF-8 and UTF-16 columns are similar.
      return utf8Column
    case .line(let line):
      lineSlice = line
    }
    guard
      let stringIndex = lineSlice.utf8.index(lineSlice.startIndex, offsetBy: utf8Column, limitedBy: lineSlice.endIndex)
    else {
      logger.fault(
        """
        UTF-8 column is past the end of the line while getting UTF-16 column of \(line):\(utf8Column) \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return lineSlice.utf16.count
    }
    return lineSlice.utf16.distance(from: lineSlice.startIndex, to: stringIndex)
  }

  /// Returns UTF-8 column offset at UTF-16 based `line:column` position.
  ///
  /// If the position does not refer to a valid position with in the snapshot, performs a bets-effort recovery and logs
  /// a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf16Column: UTF-16 column offset (zero-based).
  @inlinable
  public func utf8ColumnAt(
    line: Int,
    utf16Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Int {
    let lineSlice: Substring
    switch self.lineSlice(at: line, callerFile: callerFile, callerLine: callerLine) {
    case .beforeFirstLine, .afterLastLine:
      // This line is out-of-bounds. `lineSlice` already logged a fault.
      // Recovery by assuming that UTF-8 and UTF-16 columns are similar.
      return utf16Column
    case .line(let line):
      lineSlice = line
    }
    guard
      let stringIndex = lineSlice.utf16.index(
        lineSlice.startIndex,
        offsetBy: utf16Column,
        limitedBy: lineSlice.endIndex
      )
    else {
      logger.fault(
        """
        UTF-16 column is past the end of the line while getting UTF-8 column of \(line):\(utf16Column) \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return lineSlice.utf8.count
    }
    return lineSlice.utf8.distance(from: lineSlice.startIndex, to: stringIndex)
  }
}
