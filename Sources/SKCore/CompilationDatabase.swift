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

import SKSupport
import TSCBasic
import Foundation

/// A single compilation database command.
///
/// See https://clang.llvm.org/docs/JSONCompilationDatabase.html
public struct CompilationDatabaseCompileCommand: Equatable {

  /// The working directory for the compilation.
  public var directory: String

  /// The path of the main file for the compilation, which may be relative to `directory`.
  public var filename: String

  /// The compile command as a list of strings, with the program name first.
  public var commandLine: [String]

  /// The name of the build output, or nil.
  public var output: String? = nil

  public init(directory: String, filename: String, commandLine: [String], output: String? = nil) {
    self.directory = directory
    self.filename = filename
    self.commandLine = commandLine
    self.output = output
  }
}

extension CompilationDatabase.Command {

  /// The `URL` for this file. If `filename` is relative and `directory` is
  /// absolute, returns the concatenation. However, if both paths are relative,
  /// it falls back to `filename`, which is more likely to be the identifier
  /// that a caller will be looking for.
  public var url: URL {
    if filename.hasPrefix("/") || !directory.hasPrefix("/") {
      return URL(fileURLWithPath: filename)
    } else {
      return URL(fileURLWithPath: directory).appendingPathComponent(filename, isDirectory: false)
    }
  }
}

/// A clang-compatible compilation database.
///
/// See https://clang.llvm.org/docs/JSONCompilationDatabase.html
public protocol CompilationDatabase {
  typealias Command = CompilationDatabaseCompileCommand
  subscript(_ path: URL) -> [Command] { get }
  var allCommands: AnySequence<Command> { get }
}

/// Loads the compilation database located in `directory`, if any.
public func tryLoadCompilationDatabase(
  directory: AbsolutePath,
  _ fileSystem: FileSystem = localFileSystem
) -> CompilationDatabase? {
  return
    (try? JSONCompilationDatabase(directory: directory, fileSystem))
    ?? (try? FixedCompilationDatabase(directory: directory, fileSystem))
}

/// Fixed clang-compatible compilation database (compile_flags.txt).
///
/// Each line in the file becomes a command line argument. Example:
/// ```
/// -xc++
/// -I
/// libwidget/include/
/// ```
///
/// See https://clang.llvm.org/docs/JSONCompilationDatabase.html under Alternatives
public struct FixedCompilationDatabase: CompilationDatabase, Equatable {
  public var allCommands: AnySequence<Command> { AnySequence([]) }
  
  private let fixedArgs: [String]
  private let directory: String

  public subscript(path: URL) -> [Command] {
    [Command(directory: directory, filename: path.path, commandLine: fixedArgs + [path.path])]
  }
}

extension FixedCompilationDatabase {
  public init(directory: AbsolutePath, _ fileSystem: FileSystem = localFileSystem) throws {
    let path = directory.appending(component: "compile_flags.txt")
    try self.init(file: path, fileSystem)
  }

  public init(file: AbsolutePath, _ fileSystem: FileSystem = localFileSystem) throws {
    self.directory = file.dirname
    let bytes = try fileSystem.readFileContents(file)

    var fixedArgs: [String] = ["clang"]
    try bytes.withUnsafeData { data in
      guard let fileContents = String(data: data, encoding: .utf8) else {
        throw CompilationDatabaseDecodingError.fixedDatabaseDecordingError
      }
      
      fileContents.enumerateLines { line, _ in
        fixedArgs.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
      }
    }
    self.fixedArgs = fixedArgs
  }
}


/// The JSON clang-compatible compilation database.
///
/// Example:
///
/// ```
/// [
///   {
///     "directory": "/src",
///     "file": "/src/file.cpp",
///     "command": "clang++ file.cpp"
///   }
/// ]
/// ```
///
/// See https://clang.llvm.org/docs/JSONCompilationDatabase.html
public struct JSONCompilationDatabase: CompilationDatabase, Equatable {
  var pathToCommands: [URL: [Int]] = [:]
  var commands: [Command] = []

  public init(_ commands: [Command] = []) {
    commands.forEach { add($0) }
  }

  public subscript(_ url: URL) -> [Command] {
    if let indices = pathToCommands[url] {
      return indices.map { commands[$0] }
    }
    if let indices = pathToCommands[url.resolvingSymlinksInPath()] {
      return indices.map { commands[$0] }
    }
    return []
  }

  public var allCommands: AnySequence<Command> { AnySequence(commands) }

  public mutating func add(_ command: Command) {
    let url = command.url
    pathToCommands[url, default: []].append(commands.count)

    let canonical = url.resolvingSymlinksInPath()
    if canonical != url {
      pathToCommands[canonical, default: []].append(commands.count)
    }

    commands.append(command)
  }
}

extension JSONCompilationDatabase: Codable {
  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    while !container.isAtEnd {
      self.add(try container.decode(Command.self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try commands.forEach { try container.encode($0) }
  }
}

extension JSONCompilationDatabase {
  public init(directory: AbsolutePath, _ fileSystem: FileSystem = localFileSystem) throws {
    let path = directory.appending(component: "compile_commands.json")
    try self.init(file: path, fileSystem)
  }

  public init(file: AbsolutePath, _ fileSystem: FileSystem = localFileSystem) throws {
    let bytes = try fileSystem.readFileContents(file)
    try bytes.withUnsafeData { data in
       self = try JSONDecoder().decode(JSONCompilationDatabase.self, from: data)
    }
  }
}

enum CompilationDatabaseDecodingError: Error {
  case missingCommandOrArguments
  case fixedDatabaseDecordingError
}

extension CompilationDatabase.Command: Codable {
  private enum CodingKeys: String, CodingKey {
    case directory
    case file
    case command
    case arguments
    case output
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.directory = try container.decode(String.self, forKey: .directory)
    self.filename = try container.decode(String.self, forKey: .file)
    self.output = try container.decodeIfPresent(String.self, forKey: .output)
    if let arguments = try container.decodeIfPresent([String].self, forKey: .arguments) {
      self.commandLine = arguments
    } else if let command = try container.decodeIfPresent(String.self, forKey: .command) {
      self.commandLine = splitShellEscapedCommand(command)
    } else {
      throw CompilationDatabaseDecodingError.missingCommandOrArguments
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(directory, forKey: .directory)
    try container.encode(filename, forKey: .file)
    try container.encode(commandLine, forKey: .arguments)
    try container.encodeIfPresent(output, forKey: .output)
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
public func splitShellEscapedCommand(_ cmd: String) -> [String] {
  struct Parser {
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

  var parser = Parser(cmd[...])
  return parser.parse()
}
