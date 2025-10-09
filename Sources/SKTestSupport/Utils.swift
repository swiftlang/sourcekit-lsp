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
import SwiftExtensions

import struct TSCBasic.AbsolutePath

extension Language {
  var fileExtension: String {
    switch self {
    case .objective_c: return "m"
    case .markdown: return "md"
    case .tutorial: return "tutorial"
    default: return self.rawValue
    }
  }

  init?(fileExtension: String) {
    switch fileExtension {
    case "c": self = .c
    case "cpp": self = .cpp
    case "m": self = .objective_c
    case "mm": self = .objective_cpp
    case "swift": self = .swift
    case "md": self = .markdown
    case "tutorial": self = .tutorial
    default: return nil
    }
  }
}

extension DocumentURI {
  /// Construct a `DocumentURI` by creating a unique URI for a document of the given language.
  package init(for language: Language, testName: String = #function) {
    let testBaseName = testName.prefix(while: \.isLetter)

    #if os(Windows)
    let url = URL(fileURLWithPath: "C:/\(testBaseName)/\(UUID())/test.\(language.fileExtension)")
    #else
    let url = URL(fileURLWithPath: "/\(testBaseName)/\(UUID())/test.\(language.fileExtension)")
    #endif

    self.init(url)
  }
}

package let cleanScratchDirectories =
  (ProcessInfo.processInfo.environment["SOURCEKIT_LSP_KEEP_TEST_SCRATCH_DIR"] == nil)

package func testScratchName(testName: String = #function) -> String {
  var uuid = UUID().uuidString[...]
  if let firstDash = uuid.firstIndex(of: "-") {
    uuid = uuid[..<firstDash]
  }

  // Including the test name in the directory frequently makes path lengths of test files exceed the maximum path length
  // on Windows. Choose shorter directory names on that platform to avoid that issue.
  #if os(Windows)
  return String(uuid)
  #else
  let testBaseName = testName.prefix(while: \.isLetter)
  return "\(testBaseName)-\(uuid)"
  #endif
}

/// An empty directory in which a test with `#function` name `testName` can store temporary data.
package func testScratchDir(testName: String = #function) throws -> URL {
  #if os(Windows)
  // Use a shorter test scratch dir name on Windows to not exceed MAX_PATH length
  let testScratchDirsName = "lsp-test"
  #else
  let testScratchDirsName = "sourcekit-lsp-test-scratch"
  #endif

  let url = try FileManager.default.temporaryDirectory.realpath
    .appending(component: testScratchDirsName)
    .appending(component: testScratchName(testName: testName), directoryHint: .isDirectory)

  try? FileManager.default.removeItem(at: url)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

/// Execute `body` with a path to a temporary scratch directory for the given
/// test name.
///
/// The temporary directory will be deleted at the end of `directory` unless the
/// `SOURCEKIT_LSP_KEEP_TEST_SCRATCH_DIR` environment variable is set.
package func withTestScratchDir<T>(
  _ body: (URL) async throws -> T,
  testName: String = #function
) async throws -> T {
  let scratchDirectory = try testScratchDir(testName: testName)
  try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
  defer {
    if cleanScratchDirectories {
      try? FileManager.default.removeItem(at: scratchDirectory)
    }
  }
  return try await body(scratchDirectory)
}

var globalModuleCache: URL? {
  get throws {
    if let customModuleCache = ProcessInfo.processInfo.environment["SOURCEKIT_LSP_TEST_MODULE_CACHE"] {
      if customModuleCache.isEmpty {
        return nil
      }
      return URL(fileURLWithPath: customModuleCache)
    }
    return try FileManager.default.temporaryDirectory.realpath
      .appending(components: "sourcekit-lsp-test-scratch", "shared-module-cache")
  }
}
