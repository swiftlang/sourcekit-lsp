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

import BuildServerIntegration
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import SwiftLanguageService
import XCTest

final class SwiftCompileCommandsTest: SourceKitLSPTestCase {
  func testWorkingDirectoryIsAdded() {
    let settings = FileBuildSettings(compilerArguments: ["a", "b"], workingDirectory: "/build/root", language: .swift)
    let compileCommand = SwiftCompileCommand(settings)
    XCTAssertEqual(compileCommand.compilerArgs, ["a", "b", "-working-directory", "/build/root"])
  }

  func testNoWorkingDirectory() {
    let settings = FileBuildSettings(compilerArguments: ["a", "b"], language: .swift)
    let compileCommand = SwiftCompileCommand(settings)
    XCTAssertEqual(compileCommand.compilerArgs, ["a", "b"])
  }

  func testPreexistingWorkingDirectoryArg() {
    let settings = FileBuildSettings(
      compilerArguments: ["a", "b", "-working-directory", "/custom-root"],
      workingDirectory: "/build/root",
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    XCTAssertEqual(compileCommand.compilerArgs, ["a", "b", "-working-directory", "/custom-root"])
  }

  // MARK: - SR-12196: Working directory stripping for non-file URIs

  func testCompilerArgsForFileURI_preservesWorkingDirectory() {
    let settings = FileBuildSettings(
      compilerArguments: ["a", "b"],
      workingDirectory: "/build/root",
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    let fileURI = DocumentURI(filePath: "/path/to/file.swift", isDirectory: false)
    XCTAssertEqual(
      compileCommand.compilerArgs(for: fileURI),
      ["a", "b", "-working-directory", "/build/root"]
    )
  }

  func testCompilerArgsForNonFileURI_stripsWorkingDirectory() throws {
    let settings = FileBuildSettings(
      compilerArguments: ["a", "b"],
      workingDirectory: "/build/root",
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    let gitURI = try DocumentURI(string: "git://path/to/file.swift")
    XCTAssertEqual(
      compileCommand.compilerArgs(for: gitURI),
      ["a", "b"]
    )
  }

  func testCompilerArgsForHgURI_stripsWorkingDirectory() throws {
    let settings = FileBuildSettings(
      compilerArguments: ["a", "b"],
      workingDirectory: "/build/root",
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    let hgURI = try DocumentURI(string: "hg://path/to/file.swift")
    XCTAssertEqual(
      compileCommand.compilerArgs(for: hgURI),
      ["a", "b"]
    )
  }

  func testCompilerArgsForNonFileURI_stripsPreexistingWorkingDirectory() throws {
    let settings = FileBuildSettings(
      compilerArguments: ["a", "-working-directory", "/custom-root", "b"],
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    let nonFileURI = try DocumentURI(string: "git://path/to/file.swift")
    XCTAssertEqual(
      compileCommand.compilerArgs(for: nonFileURI),
      ["a", "b"]
    )
  }

  func testCompilerArgsForNonFileURIWithNoWorkingDirectory_unchanged() throws {
    let settings = FileBuildSettings(compilerArguments: ["a", "b"], language: .swift)
    let compileCommand = SwiftCompileCommand(settings)
    let gitURI = try DocumentURI(string: "git://path/to/file.swift")
    XCTAssertEqual(
      compileCommand.compilerArgs(for: gitURI),
      ["a", "b"]
    )
  }

  func testCompilerArgsForReferenceDocumentURI_preservesWorkingDirectory() throws {
    let settings = FileBuildSettings(
      compilerArguments: ["a", "b"],
      workingDirectory: "/build/root",
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    // Construct a valid macro expansion reference document URI.
    // Reference documents have a `primaryFile` set, so the working directory bug
    // does not affect them — sourcekitd uses `primaryFile` for file resolution.
    let macroExpansionData = MacroExpansionReferenceDocumentURLData(
      macroExpansionEditRange: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 10),
      parent: DocumentURI(filePath: "/path/to/file.swift", isDirectory: false),
      parentSelectionRange: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 10),
      bufferName: "@__swiftmacro_test"
    )
    let referenceDocURI = try ReferenceDocumentURL.macroExpansion(macroExpansionData).uri
    XCTAssertEqual(
      compileCommand.compilerArgs(for: referenceDocURI),
      ["a", "b", "-working-directory", "/build/root"]
    )
  }

  func testCompilerArgsForArbitraryNonFileScheme_stripsWorkingDirectory() throws {
    let settings = FileBuildSettings(
      compilerArguments: ["a", "b"],
      workingDirectory: "/build/root",
      language: .swift
    )
    let compileCommand = SwiftCompileCommand(settings)
    let customURI = try DocumentURI(string: "custom-scheme://host/path/to/file.swift")
    XCTAssertEqual(
      compileCommand.compilerArgs(for: customURI),
      ["a", "b"]
    )
  }
}
