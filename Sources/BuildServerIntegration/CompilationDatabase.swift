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

package import Foundation
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging
import SwiftExtensions
import TSCExtensions

#if os(Windows)
import WinSDK
#endif

/// A single compilation database command.
///
/// See https://clang.llvm.org/docs/JSONCompilationDatabase.html
package struct CompilationDatabaseCompileCommand: Equatable, Codable {
  /// The working directory for the compilation.
  package var directory: String

  /// The path of the main file for the compilation, which may be relative to `directory`.
  package var filename: String

  /// The compile command as a list of strings, with the program name first.
  package var commandLine: [String]

  /// The name of the build output, or nil.
  package var output: String? = nil

  package init(directory: String, filename: String, commandLine: [String], output: String? = nil) {
    self.directory = directory
    self.filename = filename
    self.commandLine = commandLine
    self.output = output
  }

  private enum CodingKeys: String, CodingKey {
    case directory
    case file
    case command
    case arguments
    case output
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.directory = try container.decode(String.self, forKey: .directory)
    self.filename = try container.decode(String.self, forKey: .file)
    self.output = try container.decodeIfPresent(String.self, forKey: .output)
    if let arguments = try container.decodeIfPresent([String].self, forKey: .arguments) {
      self.commandLine = arguments
    } else if let command = try container.decodeIfPresent(String.self, forKey: .command) {
      #if os(Windows)
      self.commandLine = splitWindowsCommandLine(command, initialCommandName: true)
      #else
      self.commandLine = splitShellEscapedCommand(command)
      #endif
    } else {
      throw CompilationDatabaseDecodingError.missingCommandOrArguments
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(directory, forKey: .directory)
    try container.encode(filename, forKey: .file)
    try container.encode(commandLine, forKey: .arguments)
    try container.encodeIfPresent(output, forKey: .output)
  }

  /// The `DocumentURI` for this file. If `filename` is relative and `directory` is
  /// absolute, returns the concatenation. However, if both paths are relative,
  /// it falls back to `filename`, which is more likely to be the identifier
  /// that a caller will be looking for.
  package var uri: DocumentURI {
    if filename.isAbsolutePath || !directory.isAbsolutePath {
      return DocumentURI(filePath: filename, isDirectory: false)
    } else {
      return DocumentURI(URL(fileURLWithPath: directory).appendingPathComponent(filename, isDirectory: false))
    }
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
package struct JSONCompilationDatabase: Equatable, Codable {
  private var pathToCommands: [DocumentURI: [Int]] = [:]
  var commands: [CompilationDatabaseCompileCommand] = []

  package init(_ commands: [CompilationDatabaseCompileCommand] = []) {
    for command in commands {
      add(command)
    }
  }

  package init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    while !container.isAtEnd {
      self.add(try container.decode(CompilationDatabaseCompileCommand.self))
    }
  }

  /// Loads the compilation database located in `directory`, if any.
  ///
  /// - Returns: `nil` if `compile_commands.json` was not found
  package init(directory: URL) throws {
    let path = directory.appendingPathComponent(JSONCompilationDatabaseBuildServer.dbName)
    try self.init(file: path)
  }

  /// Loads the compilation database from `file`
  /// - Returns: `nil` if the file does not exist
  package init(file: URL) throws {
    let data = try Data(contentsOf: file)
    self = try JSONDecoder().decode(JSONCompilationDatabase.self, from: data)
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try commands.forEach { try container.encode($0) }
  }

  package subscript(_ uri: DocumentURI) -> [CompilationDatabaseCompileCommand] {
    if let indices = pathToCommands[uri] {
      return indices.map { commands[$0] }
    }
    if let fileURL = try? uri.fileURL?.realpath, let indices = pathToCommands[DocumentURI(fileURL)] {
      return indices.map { commands[$0] }
    }
    return []
  }

  private mutating func add(_ command: CompilationDatabaseCompileCommand) {
    let uri = command.uri
    pathToCommands[uri, default: []].append(commands.count)

    if let symlinkTarget = uri.symlinkTarget {
      pathToCommands[symlinkTarget, default: []].append(commands.count)
    }

    commands.append(command)
  }
}

enum CompilationDatabaseDecodingError: Error {
  case missingCommandOrArguments
  case fixedDatabaseDecodingError
}

fileprivate extension String {
  var isAbsolutePath: Bool {
    #if os(Windows)
    Array(self.utf16).withUnsafeBufferPointer { buffer in
      return !PathIsRelativeW(buffer.baseAddress)
    }
    #else
    return self.hasPrefix("/")
    #endif
  }
}
