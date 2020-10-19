//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Position within a text document, expressed as a zero-based line and column (utf-16 code unit offset).
public struct Position: Hashable {

  /// Line number within a document (zero-based).
  public var line: Int

  /// UTF-16 code-unit offset from the start of a line (zero-based).
  public var utf16index: Int

  public init(line: Int, utf16index: Int) {
    self.line = line
    self.utf16index = utf16index
  }
}

extension Position: Codable {
  private enum CodingKeys: String, CodingKey {
    case line
    case utf16index = "character"
  }
}

extension Position: Comparable {
  public static func < (lhs: Position, rhs: Position) -> Bool {
    return (lhs.line, lhs.utf16index) < (rhs.line, rhs.utf16index)
  }
}

extension Position: LSPAnyCodable {
  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard case .int(let line) = dictionary[CodingKeys.line.stringValue],
          case .int(let utf16index) = dictionary[CodingKeys.utf16index.stringValue] else
    {
      return nil
    }
    self.line = line
    self.utf16index = utf16index
  }

  public func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      CodingKeys.line.stringValue: .int(line),
      CodingKeys.utf16index.stringValue: .int(utf16index)
    ])
  }
}

extension Position: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    "\(line + 1):\(utf16index+1)"
  }

  public var debugDescription: String {
    "Position(line: \(line), utf16index: \(utf16index))"
  }
}
