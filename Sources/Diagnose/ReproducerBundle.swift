//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftExtensions
import ToolchainRegistry

import struct TSCBasic.AbsolutePath

/// Create a folder that contains all files that should be necessary to reproduce a sourcekitd crash.
/// - Parameters:
///   - requestInfo: The reduced request info
///   - toolchain: The toolchain that was used to reduce the request
///   - bundlePath: The path to which to write the reproducer bundle
func makeReproducerBundle(for requestInfo: RequestInfo, toolchain: Toolchain, bundlePath: URL) throws {
  try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
  try requestInfo.fileContents.write(
    to: bundlePath.appendingPathComponent("input.swift"),
    atomically: true,
    encoding: .utf8
  )
  if let toolchainPath = toolchain.path {
    try toolchainPath.realpath.filePath
      .write(
        to: bundlePath.appendingPathComponent("toolchain.txt"),
        atomically: true,
        encoding: .utf8
      )
  }
  if requestInfo.requestTemplate == RequestInfo.fakeRequestTemplateForFrontendIssues {
    let command =
      "swift-frontend \\\n"
      + requestInfo.compilerArgs.replacing(["$FILE"], with: ["./input.swift"]).joined(separator: " \\\n")
    try command.write(to: bundlePath.appendingPathComponent("command.sh"), atomically: true, encoding: .utf8)
  } else {
    let request = try requestInfo.request(for: URL(fileURLWithPath: "/input.swift"))
    try request.write(
      to: bundlePath.appendingPathComponent("request.yml"),
      atomically: true,
      encoding: .utf8
    )
  }
  for compilerArg in requestInfo.compilerArgs {
    // Find the first slash so we are also able to copy files from eg.
    // `-fmodule-map-file=/path/to/module.modulemap`
    // `-I/foo/bar`
    guard let firstSlash = compilerArg.firstIndex(of: "/") else {
      continue
    }
    let path = compilerArg[firstSlash...]
    guard !path.contains(".app"), !path.contains(".xctoolchain"), !path.contains("/usr/") else {
      // Don't include files in Xcode (.app), Xcode toolchains or usr because they are most likely binary files that
      // aren't user specific and would bloat the reproducer bundle.
      continue
    }
    let dest = URL(fileURLWithPath: try bundlePath.filePath + path)
    try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.copyItem(at: URL(fileURLWithPath: String(path)), to: dest)
  }
}
