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

// MARK: - Unix

fileprivate struct UnixCommandParser {
  var content: Substring
  var i: Substring.UTF8View.Index
  var result: [String] = []

  var ch: UInt8 { self.content.utf8[i] }
  var done: Bool { self.content.endIndex == i }

  init(_ string: Substring) {
    self.content = string
    self.i = self.content.utf8.startIndex
  }

  mutating func next() {
    i = content.utf8.index(after: i)
  }

  mutating func next(expect c: UInt8) {
    assert(c == ch)
    next()
  }

  mutating func parse() -> [String] {
    while !done {
      switch ch {
      case UInt8(ascii: " "): next()
      default: parseString()
      }
    }
    return result
  }

  mutating func parseString() {
    var str = ""
    STRING: while !done {
      switch ch {
      case UInt8(ascii: " "): break STRING
      case UInt8(ascii: "\""): parseDoubleQuotedString(into: &str)
      case UInt8(ascii: "\'"): parseSingleQuotedString(into: &str)
      default: parsePlainString(into: &str)
      }
    }
    result.append(str)
  }

  mutating func parseDoubleQuotedString(into str: inout String) {
    next(expect: UInt8(ascii: "\""))
    var start = i
    while !done {
      switch ch {
      case UInt8(ascii: "\""):
        str += content[start..<i]
        next()
        return
      case UInt8(ascii: "\\"):
        str += content[start..<i]
        next()
        start = i
        if !done { fallthrough }
      default:
        next()
      }
    }
    str += content[start..<i]
  }

  mutating func parseSingleQuotedString(into str: inout String) {
    next(expect: UInt8(ascii: "\'"))
    let start = i
    while !done {
      switch ch {
      case UInt8(ascii: "\'"):
        str += content[start..<i]
        next()
        return
      default:
        next()
      }
    }
    str += content[start..<i]
  }

  mutating func parsePlainString(into str: inout String) {
    var start = i
    while !done {
      let _ch = ch
      switch _ch {
      case UInt8(ascii: "\""), UInt8(ascii: "\'"), UInt8(ascii: " "):
        str += content[start..<i]
        return
      case UInt8(ascii: "\\"):
        str += content[start..<i]
        next()
        start = i
        if !done { fallthrough }
      default:
        next()
      }
    }
    str += content[start..<i]
  }
}

/// Split and unescape a shell-escaped command line invocation.
///
/// Examples:
///
/// ```
/// abc def -> ["abc", "def"]
/// abc\ def -> ["abc def"]
/// abc"\""def -> ["abc\"def"]
/// abc'\"'def -> ["abc\\"def"]
/// ```
///
/// See clang's `unescapeCommandLine()`.
package func splitShellEscapedCommand(_ cmd: String) -> [String] {
  var parser = UnixCommandParser(cmd[...])
  return parser.parse()
}

// MARK: - Windows

fileprivate extension Character {
  var isWhitespace: Bool {
    switch self {
    case " ", "\t":
      return true
    default:
      return false
    }
  }

  var isWhitespaceOrNull: Bool {
    return self.isWhitespace || self == "\0"
  }

  func isWindowsSpecialChar(inCommandName: Bool) -> Bool {
    if isWhitespace {
      return true
    }
    if self == #"""# {
      return true
    }
    if !inCommandName && self == #"\"# {
      return true
    }
    return false
  }
}

fileprivate struct WindowsCommandParser {
  /// The content of the entire command that shall be parsed.
  private let content: String

  /// Whether we are parsing the initial command name. In this mode `\` is not treated as escaping the quote
  /// character.
  private var parsingCommandName: Bool

  /// An index into `content`, pointing to the character that we are currently parsing.
  private var currentCharacterIndex: String.UTF8View.Index

  /// The split command line arguments.
  private var result: [String] = []

  /// The character that is currently being parsed.
  ///
  /// `nil` if we have reached the end of `content`.
  private var currentCharacter: Character? {
    guard currentCharacterIndex < content.endIndex else {
      return nil
    }
    return self.content[currentCharacterIndex]
  }

  /// The character after `currentCharacter`.
  ///
  /// `nil` if we have reached the end of `content`.
  private var peek: Character? {
    let nextIndex = content.index(after: currentCharacterIndex)
    if nextIndex < content.endIndex {
      return content[nextIndex]
    } else {
      return nil
    }
  }

  init(_ string: String, initialCommandName: Bool) {
    self.content = string
    self.currentCharacterIndex = self.content.startIndex
    self.parsingCommandName = initialCommandName
  }

  /// Designated entry point to split a Windows command line invocation.
  mutating func parse() -> [String] {
    while let currentCharacter {
      if currentCharacter.isWhitespaceOrNull {
        // Consume any whitespace separating arguments.
        _ = consume()
      } else {
        result.append(parseSingleArgument())
      }
    }
    return result
  }

  /// Consume the current character.
  private mutating func consume() -> Character {
    guard let character = currentCharacter else {
      preconditionFailure("Nothing to consume")
    }
    currentCharacterIndex = content.index(after: currentCharacterIndex)
    return character
  }

  /// Consume the current character, asserting that it is `expectedCharacter`
  private mutating func consume(expect expectedCharacter: Character) {
    assert(currentCharacter == expectedCharacter)
    _ = consume()
  }

  /// Parses a single argument, consuming its characters and returns the parsed arguments with all escaping unfolded
  /// (e.g. `\"` gets returned as `"`)
  ///
  /// Afterwards the parser points to the character after the argument.
  mutating func parseSingleArgument() -> String {
    var str = ""
    while let currentCharacter {
      if !currentCharacter.isWindowsSpecialChar(inCommandName: parsingCommandName) {
        str.append(consume())
        continue
      }
      if currentCharacter.isWhitespaceOrNull {
        parsingCommandName = false
        return str
      } else if currentCharacter == "\"" {
        str += parseQuoted()
      } else if currentCharacter == #"\"# {
        assert(!parsingCommandName, "else we'd have treated it as a normal char");
        str.append(parseBackslash())
      } else {
        preconditionFailure("unexpected special character");
      }
    }
    return str
  }

  /// Assuming that we are positioned at a `"`, parse a quoted string and return the string contents without the
  /// quotes.
  mutating func parseQuoted() -> String {
    // Discard the opening quote. Its not part of the unescaped text.
    consume(expect: "\"")

    var str = ""
    while let currentCharacter {
      switch currentCharacter {
      case "\"":
        if peek == "\"" {
          // Two adjacent quotes inside a quoted string are an escaped single quote. For example
          // `" a "" b "`
          // represents the string
          // ` a " b `
          consume(expect: "\"")
          consume(expect: "\"")
          str += "\""
        } else {
          // We have found the closing quote. Discard it and return.
          consume(expect: "\"")
          return str
        }
      case "\\" where !parsingCommandName:
        str.append(parseBackslash())
      default:
        str.append(consume())
      }
    }
    return str
  }

  /// Backslashes are interpreted in a rather complicated way in the Windows-style
  /// command line, because backslashes are used both to separate path and to
  /// escape double quote. This method consumes runs of backslashes as well as the
  /// following double quote if it's escaped.
  ///
  ///  * If an even number of backslashes is followed by a double quote, one
  ///    backslash is output for every pair of backslashes, and the last double
  ///    quote remains unconsumed. The double quote will later be interpreted as
  ///    the start or end of a quoted string in the main loop outside of this
  ///    function.
  ///
  ///  * If an odd number of backslashes is followed by a double quote, one
  ///    backslash is output for every pair of backslashes, and a double quote is
  ///    output for the last pair of backslash-double quote. The double quote is
  ///    consumed in this case.
  ///
  ///  * Otherwise, backslashes are interpreted literally.
  mutating func parseBackslash() -> String {
    var str: String = ""

    let firstNonBackslashIndex = content[currentCharacterIndex...].firstIndex(where: { $0 != "\\" }) ?? content.endIndex
    let numberOfBackslashes = content.distance(from: currentCharacterIndex, to: firstNonBackslashIndex)

    if firstNonBackslashIndex != content.endIndex && content[firstNonBackslashIndex] == "\"" {
      str += String(repeating: "\\", count: numberOfBackslashes / 2)
      if numberOfBackslashes.isMultiple(of: 2) {
        // We have an even number of backslashes. Just add the escaped backslashes to `str` and return to parse the
        // quote in the outer function.
        currentCharacterIndex = firstNonBackslashIndex
      } else {
        // We have an odd number of backslashes. The last backslash escapes the quote.
        str += "\""
        currentCharacterIndex = content.index(after: firstNonBackslashIndex)
      }
      return str
    }

    // The sequence of backslashes is not followed by quotes. Interpret them literally.
    str += String(repeating: "\\", count: numberOfBackslashes)
    currentCharacterIndex = firstNonBackslashIndex
    return str
  }
}

// Sometimes, this function will be handling a full command line including an
// executable pathname at the start. In that situation, the initial pathname
// needs different handling from the following arguments, because when
// CreateProcess or cmd.exe scans the pathname, it doesn't treat \ as
// escaping the quote character, whereas when libc scans the rest of the
// command line, it does.
package func splitWindowsCommandLine(_ cmd: String, initialCommandName: Bool) -> [String] {
  var parser = WindowsCommandParser(cmd, initialCommandName: initialCommandName)
  return parser.parse()
}
