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

import Foundation
import SKUtilities
import SwiftExtensions
import TSCExtensions

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process

/// Given a path to a compiler, which might be a symlink to `swiftly`, this type determines the compiler executable in
/// an actual toolchain. It also caches the results. The client needs to invalidate the cache if the path that swiftly
/// might resolve to has changed, eg. because `.swift-version` has been updated.
actor SwiftlyResolver {
  private struct CacheKey: Hashable {
    let compiler: URL
    let workingDirectory: URL?
  }

  private var cache: LRUCache<CacheKey, Result<URL?, any Error>> = LRUCache(capacity: 100)

  /// Check if `compiler` is a symlink to `swiftly`. If so, find the executable in the toolchain that swiftly resolves
  /// to within the given working directory and return the URL of the corresponding compiler in that toolchain.
  /// If `compiler` does not resolve to `swiftly`, return `nil`.
  func resolve(compiler: URL, workingDirectory: URL?) async throws -> URL? {
    let cacheKey = CacheKey(compiler: compiler, workingDirectory: workingDirectory)
    if let cached = cache[cacheKey] {
      return try cached.get()
    }
    let computed: Result<URL?, any Error>
    do {
      computed = .success(
        try await resolveSwiftlyTrampolineImpl(compiler: compiler, workingDirectory: workingDirectory)
      )
    } catch {
      computed = .failure(error)
    }
    cache[cacheKey] = computed
    return try computed.get()
  }

  private func resolveSwiftlyTrampolineImpl(compiler: URL, workingDirectory: URL?) async throws -> URL? {
    let realpath = try compiler.realpath
    guard realpath.lastPathComponent == "swiftly" else {
      return nil
    }
    let swiftlyResult = try await Process.run(
      arguments: [realpath.filePath, "use", "-p"],
      workingDirectory: try AbsolutePath(validatingOrNil: workingDirectory?.filePath)
    )
    let swiftlyToolchain = URL(
      fileURLWithPath: try swiftlyResult.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
    )
    let resolvedCompiler = swiftlyToolchain.appending(components: "usr", "bin", compiler.lastPathComponent)
    if FileManager.default.fileExists(at: resolvedCompiler) {
      return resolvedCompiler
    }
    return nil
  }

  func clearCache() {
    cache.removeAll()
  }
}
