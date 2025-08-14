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

package import IndexStoreDB
package import LanguageServerProtocol
import SKLogging
import SKUtilities
package import SwiftSyntax

extension DocumentSnapshot {

  // MARK: String.Index <-> Raw UTF-8

  /// Converts the given UTF-8 offset to `String.Index`.
  ///
  /// If the offset is out-of-bounds of the snapshot, returns the closest valid index and logs a fault containing the
  /// file and line of the caller (from `callerFile` and `callerLine`).
  package func indexOf(utf8Offset: Int, callerFile: StaticString = #fileID, callerLine: UInt = #line) -> String.Index {
    guard utf8Offset >= 0 else {
      logger.fault(
        """
        UTF-8 offset \(utf8Offset) is negative while converting it to String.Index \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return text.startIndex
    }
    guard let index = text.utf8.index(text.startIndex, offsetBy: utf8Offset, limitedBy: text.endIndex) else {
      logger.fault(
        """
        UTF-8 offset \(utf8Offset) is past end of file while converting it to String.Index \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return text.endIndex
    }
    return index
  }

  // MARK: Position <-> Raw UTF-8 offset

  /// Converts the given UTF-16-based line:column position to the UTF-8 offset of that position within the source file.
  ///
  /// If `position` does not refer to a valid position with in the snapshot, returns the offset of the closest valid
  /// position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  package func utf8Offset(of position: Position, callerFile: StaticString = #fileID, callerLine: UInt = #line) -> Int {
    return lineTable.utf8OffsetOf(
      line: position.line,
      utf16Column: position.utf16index,
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  /// Converts the given UTF-8 offset to a UTF-16-based line:column position.
  ///
  /// If the offset is after the end of the snapshot, returns `nil` and logs a fault containing the file and line of
  /// the caller (from `callerFile` and `callerLine`).
  package func positionOf(utf8Offset: Int, callerFile: StaticString = #fileID, callerLine: UInt = #line) -> Position {
    let (line, utf16Column) = lineTable.lineAndUTF16ColumnOf(
      utf8Offset: utf8Offset,
      callerFile: callerFile,
      callerLine: callerLine
    )
    return Position(line: line, utf16index: utf16Column)
  }

  /// Converts the given UTF-16 based line:column range to a UTF-8 based offset range.
  ///
  /// If the bounds of the range do not refer to a valid positions with in the snapshot, this function adjusts them to
  /// the closest valid positions and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  package func utf8OffsetRange(
    of range: Range<Position>,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<Int> {
    let startOffset = utf8Offset(of: range.lowerBound, callerFile: callerFile, callerLine: callerLine)
    let endOffset = utf8Offset(of: range.upperBound, callerFile: callerFile, callerLine: callerLine)
    return startOffset..<endOffset
  }

  // MARK: Position <-> String.Index

  /// Converts the given UTF-16-based `line:column` position to a `String.Index`.
  ///
  /// If `position` does not refer to a valid position with in the snapshot, returns the index of the closest valid
  /// position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  package func index(
    of position: Position,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> String.Index {
    return lineTable.stringIndexOf(
      line: position.line,
      utf16Column: position.utf16index,
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  /// Converts the given UTF-16-based `line:column` range to a `String.Index` range.
  ///
  /// If the bounds of the range do not refer to a valid positions with in the snapshot, this function adjusts them to
  /// the closest valid positions and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  package func indexRange(
    of range: Range<Position>,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<String.Index> {
    return self.index(of: range.lowerBound)..<self.index(of: range.upperBound)
  }

  /// Converts the given UTF-8 based line:column position to a UTF-16 based line-column position.
  ///
  /// If the UTF-8 based line:column pair does not refer to a valid position within the snapshot, returns the closest
  /// valid position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  package func positionOf(
    zeroBasedLine: Int,
    utf8Column: Int,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Position {
    let utf16Column = lineTable.utf16ColumnAt(
      line: zeroBasedLine,
      utf8Column: utf8Column,
      callerFile: callerFile,
      callerLine: callerLine
    )
    return Position(line: zeroBasedLine, utf16index: utf16Column)
  }

  /// Converts the given `String.Index` to a UTF-16-based line:column position.
  package func position(of index: String.Index, fromLine: Int = 0) -> Position {
    let (line, utf16Column) = lineTable.lineAndUTF16ColumnOf(index, fromLine: fromLine)
    return Position(line: line, utf16index: utf16Column)
  }

  // MARK: Position <-> AbsolutePosition

  /// Converts the given UTF-8-offset-based `AbsolutePosition` to a UTF-16-based line:column.
  ///
  /// If the `AbsolutePosition` out of bounds of the source file, returns the closest valid position and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  package func position(
    of position: AbsolutePosition,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Position {
    return positionOf(utf8Offset: position.utf8Offset, callerFile: callerFile, callerLine: callerLine)
  }

  /// Converts the given UTF-16-based line:column `Position` to a UTF-8-offset-based `AbsolutePosition`.
  ///
  /// If the UTF-16 based line:column pair does not refer to a valid position within the snapshot, returns the closest
  /// valid position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  package func absolutePosition(
    of position: Position,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> AbsolutePosition {
    let offset = utf8Offset(of: position, callerFile: callerFile, callerLine: callerLine)
    return AbsolutePosition(utf8Offset: offset)
  }

  /// Converts the lower and upper bound of the given UTF-8-offset-based `AbsolutePosition` range to a UTF-16-based
  /// line:column range for use in LSP.
  ///
  /// If the bounds of the range do not refer to a valid positions with in the snapshot, this function adjusts them to
  /// the closest valid positions and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  package func absolutePositionRange(
    of range: Range<AbsolutePosition>,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<Position> {
    let lowerBound = self.position(of: range.lowerBound, callerFile: callerFile, callerLine: callerLine)
    let upperBound = self.position(of: range.upperBound, callerFile: callerFile, callerLine: callerLine)
    return lowerBound..<upperBound
  }

  /// Extracts the range of the given syntax node in terms of positions within
  /// this source file.
  package func range(
    of node: some SyntaxProtocol,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<Position> {
    let lowerBound = self.position(of: node.position, callerFile: callerFile, callerLine: callerLine)
    let upperBound = self.position(of: node.endPosition, callerFile: callerFile, callerLine: callerLine)
    return lowerBound..<upperBound
  }

  /// Converts the given UTF-16-based line:column range to a UTF-8-offset-based `ByteSourceRange`.
  ///
  /// If the bounds of the range do not refer to a valid positions with in the snapshot, this function adjusts them to
  /// the closest valid positions and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  package func byteSourceRange(
    of range: Range<Position>,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Range<AbsolutePosition> {
    let utf8OffsetRange = utf8OffsetRange(of: range, callerFile: callerFile, callerLine: callerLine)
    return Range<AbsolutePosition>(
      position: AbsolutePosition(utf8Offset: utf8OffsetRange.startIndex),
      length: SourceLength(utf8Length: utf8OffsetRange.count)
    )
  }

  // MARK: Position <-> RenameLocation

  /// Converts the given UTF-8-based line:column `RenamedLocation` to a UTF-16-based line:column `Position`.
  ///
  /// If the UTF-8 based line:column pair does not refer to a valid position within the snapshot, returns the closest
  /// valid position and logs a fault containing the file and line of the caller (from `callerFile` and `callerLine`).
  package func position(
    of renameLocation: RenameLocation,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Position {
    return positionOf(
      zeroBasedLine: renameLocation.line - 1,
      utf8Column: renameLocation.utf8Column - 1,
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  // MAR: Position <-> SymbolLocation

  /// Converts the given UTF-8-offset-based `SymbolLocation` to a UTF-16-based line:column `Position`.
  ///
  /// If the UTF-8 offset is out-of-bounds of the snapshot, returns the closest valid position and logs a fault
  /// containing the file and line of the caller (from `callerFile` and `callerLine`).
  package func position(
    of symbolLocation: SymbolLocation,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> Position {
    return positionOf(
      zeroBasedLine: symbolLocation.line - 1,
      utf8Column: symbolLocation.utf8Column - 1,
      callerFile: callerFile,
      callerLine: callerLine
    )
  }

  // MARK: AbsolutePosition <-> RenameLocation

  /// Converts the given UTF-8-based line:column `RenamedLocation` to a UTF-8-offset-based `AbsolutePosition`.
  ///
  /// If the UTF-8 based line:column pair does not refer to a valid position within the snapshot, returns the offset of
  /// the closest valid position and logs a fault containing the file and line of the caller (from `callerFile` and
  /// `callerLine`).
  package func absolutePosition(
    of renameLocation: RenameLocation,
    callerFile: StaticString = #fileID,
    callerLine: UInt = #line
  ) -> AbsolutePosition {
    let utf8Offset = lineTable.utf8OffsetOf(
      line: renameLocation.line - 1,
      utf8Column: renameLocation.utf8Column - 1,
      callerFile: callerFile,
      callerLine: callerLine
    )
    return AbsolutePosition(utf8Offset: utf8Offset)
  }
}
