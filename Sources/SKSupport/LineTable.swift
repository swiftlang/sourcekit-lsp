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

  public struct Line: Hashable {

    /// The zero-based line number.
    public var index: Int

    /// The UTF-8 byte offset of the start of the line.
    public var utf8Offset: Int

    /// The UTF-16 code-unit offset of the start of the line.
    public var utf16Offset: Int { return content.startIndex.encodedOffset }

    /// The content of the line, including the newline.
    public var content: Substring

    @inlinable
    public init(index: Int, utf8Offset: Int, content: Substring) {
      self.index = index
      self.utf8Offset = utf8Offset
      self.content = content
    }
  }

  @usableFromInline
  struct LineData: Hashable {
    @usableFromInline
    var stringIndex: String.Index
    @usableFromInline
    var utf8Offset: Int
  }

  @usableFromInline
  var impl: [LineData]

  public var content: String

  public init(_ string: String) {
    content = string

    if content.isEmpty {
      impl = [LineData(stringIndex: content.startIndex, utf8Offset: 0)]
      return
    }

    var i = string.startIndex
    var utf8Offset = 0
    var prevUTF16: UInt16 = 0

    impl = [LineData(stringIndex: i, utf8Offset: utf8Offset)]

    let utf16 = string.utf16

    while i != string.endIndex {
      let next = utf16.index(after: i)

      let c = utf16[i]
      utf8Offset += _utf8Count(c, prev: prevUTF16)
      prevUTF16 = c

      if c == /*newline*/10 {
        impl.append(LineData(stringIndex: next, utf8Offset: utf8Offset))
      }

      i = next
    }
  }

  /// The number of lines.
  @inlinable
  public var count: Int { return impl.count }

  /// Returns the given (zero-based) line.
  @inlinable
  public subscript(_ line: Int) -> Line {
    let data = impl[line]
    return Line(
      index: line,
      utf8Offset: data.utf8Offset,
      content: content[data.stringIndex..<nextLineStart(line)]
    )
  }

  /// Returns the line containing the given UTF-8 byte offset.
  @inlinable
  public subscript(utf8Offset offset: Int) -> Line {
    // FIXME: binary search
    for (i, data) in impl.enumerated() {
      if data.utf8Offset > offset {
        assert(i > 0)
        return self[i - 1]
      }
    }
    return self[count - 1]
  }

  @inlinable
  public subscript(utf16Offset offset: Int) -> Line {
    // FIXME: binary search
    for (i, data) in impl.enumerated() {
      if data.stringIndex.encodedOffset > offset {
        assert(i > 0)
        return self[i - 1]
      }
    }
    return self[count - 1]
  }

  @inlinable
  func nextLineStart(_ line: Int) -> String.Index {
    if line == count - 1 {
      return content.endIndex 
    } else {
      return impl[line + 1].stringIndex
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
    let start = String.Index(encodedOffset: self[fromLine].utf16Offset + fromOff)
    let end = String.Index(encodedOffset: self[toLine].utf16Offset + toOff)

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
  @inlinable
  mutating public func replace(
    fromLine: Int,
    utf16Offset fromOff: Int,
    utf16Length: Int,
    with replacement: String) 
  {
    let endOff = self[fromLine].utf16Offset + fromOff + utf16Length
    let endLine = self[utf16Offset: endOff]

    self.replace(fromLine: fromLine, utf16Offset: fromOff, toLine: endLine.index, utf16Offset: endOff - endLine.utf16Offset, with: replacement)
  }
}

// Note: This is copied from the stdlib.
// Used to calculate a running count. For non-BMP scalars, it's important if the
// prior code unit was a leading surrogate (validity).
private func _utf8Count(_ utf16CU: UInt16, prev: UInt16) -> Int {
  switch utf16CU {
  case 0..<0x80: return 1
  case 0x80..<0x800: return 2
  case 0x800..<0xDC00: return 3
  case 0xDC00..<0xE000: return UTF16.isLeadSurrogate(prev) ? 1 : 3
  default: return 3
  }
}
