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

// MARK: - Position translation

extension LineTable {
  // MARK: line:column <-> String.Index

  /// Converts the given UTF-16-based `line:column`` position to a `String.Index`.
  ///
  /// If the position does not refer to a valid position with in the source file, returns `nil` and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf16Column: UTF-16 column offset (zero-based).
  @inlinable
  public func stringIndexOf(
    line: Int,
    utf16Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> String.Index? {
    guard line < count else {
      logger.fault(
        """
        Unable to get string index for \(line):\(utf16Column) (UTF-16) because line is out of range \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return nil
    }
    let lineSlice = self[line]
    guard let index = content.utf16.index(lineSlice.startIndex, offsetBy: utf16Column, limitedBy: lineSlice.endIndex)
    else {
      logger.fault(
        """
        Unable to get string index for \(line):\(utf16Column) (UTF-16) because column is out of range \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return nil
    }
    return index
  }

  /// Converts the given UTF-8-based `line:column`` position to a `String.Index`.
  ///
  /// If the position does not refer to a valid position with in the source file, returns `nil` and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf8Column: UTF-8 column offset (zero-based).
  @inlinable
  public func stringIndexOf(
    line: Int,
    utf8Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> String.Index? {
    guard 0 <= line, line < count else {
      logger.fault(
        """
        Unable to get string index for \(line):\(utf8Column) (UTF-8) because line is out of range \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return nil
    }
    guard 0 <= utf8Column else {
      logger.fault(
        """
        Unable to get string index for \(line):\(utf8Column) (UTF-8) because column is out of range \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return nil
    }
    let lineSlice = self[line]
    return content.utf8.index(lineSlice.startIndex, offsetBy: utf8Column, limitedBy: lineSlice.endIndex)
  }

  // MARK: line:column <-> UTF-8 offset

  /// Converts the given UTF-16-based `line:column`` position to a UTF-8 offset within the source file.
  ///
  /// If the position does not refer to a valid position with in the source file, returns `nil` and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf16Column: UTF-16 column offset (zero-based).
  @inlinable
  public func utf8OffsetOf(
    line: Int,
    utf16Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Int? {
    guard
      let stringIndex = stringIndexOf(
        line: line,
        utf16Column: utf16Column,
        callerFile: callerFile,
        callerLine: callerLine
      )
    else {
      return nil
    }
    return content.utf8.distance(from: content.startIndex, to: stringIndex)
  }

  /// Converts the given UTF-8-based `line:column`` position to a UTF-8 offset within the source file.
  ///
  /// If the position does not refer to a valid position with in the source file, returns `nil` and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf8Column: UTF-8 column offset (zero-based).
  @inlinable
  public func utf8OffsetOf(
    line: Int,
    utf8Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Int? {
    guard
      let stringIndex = stringIndexOf(
        line: line,
        utf8Column: utf8Column,
        callerFile: callerFile,
        callerLine: callerLine
      )
    else {
      return nil
    }
    return content.utf8.distance(from: content.startIndex, to: stringIndex)
  }

  /// Converts the given UTF-16-based line:column position to the UTF-8 offset of that position within the source file.
  ///
  /// If the position does not refer to a valid position with in the snapshot, returns `nil` and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter utf8Offset: UTF-8 buffer offset (zero-based).
  @inlinable
  public func lineAndUTF16ColumnOf(
    utf8Offset: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> (line: Int, utf16Column: Int)? {
    guard utf8Offset <= content.utf8.count else {
      logger.fault(
        """
        Unable to get line and UTF-16 column for UTF-8 offset \(utf8Offset) because offset is out of range \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return nil
    }
    return lineAndUTF16ColumnOf(content.utf8.index(content.startIndex, offsetBy: utf8Offset))
  }

  /// Converts the given UTF-8-based line:column position to the UTF-8 offset of that position within the source file.
  ///
  /// If the position does not refer to a valid position with in the snapshot, returns `nil` and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  @inlinable func lineAndUTF8ColumnOf(
    utf8Offset: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> (line: Int, utf8Column: Int)? {
    guard
      let (line, utf16Column) = lineAndUTF16ColumnOf(
        utf8Offset: utf8Offset,
        callerFile: callerFile,
        callerLine: callerLine
      )
    else {
      return nil
    }
    guard
      let utf8Column = utf8ColumnAt(
        line: line,
        utf16Column: utf16Column,
        callerFile: callerFile,
        callerLine: callerLine
      )
    else {
      return nil
    }
    return (line, utf8Column)
  }

  // MARK: UTF-8 line:column <-> UTF-16 line:column

  /// Returns UTF-16 column offset at UTF-8 based `line:column` position.
  ///
  /// If the position does not refer to a valid position with in the snapshot, returns `nil` and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf8Column: UTF-8 column offset (zero-based).
  @inlinable
  public func utf16ColumnAt(
    line: Int,
    utf8Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Int? {
    return convertColumn(
      line: line,
      column: utf8Column,
      indexFunction: content.utf8.index(_:offsetBy:limitedBy:),
      distanceFunction: content.utf16.distance(from:to:),
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  /// Returns UTF-8 column offset at UTF-16 based `line:column` position.
  ///
  /// If the position does not refer to a valid position with in the snapshot, returns `nil` and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  ///
  /// - parameter line: Line number (zero-based).
  /// - parameter utf16Column: UTF-16 column offset (zero-based).
  @inlinable
  public func utf8ColumnAt(
    line: Int,
    utf16Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Int? {
    return convertColumn(
      line: line,
      column: utf16Column,
      indexFunction: content.utf16.index(_:offsetBy:limitedBy:),
      distanceFunction: content.utf8.distance(from:to:),
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  @inlinable
  func convertColumn(
    line: Int,
    column: Int,
    indexFunction: (Substring.Index, Int, Substring.Index) -> Substring.Index?,
    distanceFunction: (Substring.Index, Substring.Index) -> Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Int? {
    guard line < count else {
      logger.fault(
        """
        Unable to convert column of \(line):\(column) because line is out of range \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return nil
    }
    let lineSlice = self[line]
    guard let targetIndex = indexFunction(lineSlice.startIndex, column, lineSlice.endIndex) else {
      logger.fault(
        """
        Unable to convert column of \(line):\(column) because column is out of range \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return nil
    }
    return distanceFunction(lineSlice.startIndex, targetIndex)
  }
}
