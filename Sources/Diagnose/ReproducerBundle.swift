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

/// Create a folder that contains all files that should be necessary to reproduce a sourcekitd crash.
func makeReproducerBundle(for requestInfo: RequestInfo) throws -> URL {
  let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
  let bundlePath = FileManager.default.temporaryDirectory
    .appendingPathComponent("sourcekitd-reproducer-\(date)")
  try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)

  try requestInfo.fileContents.write(
    to: bundlePath.appendingPathComponent("input.swift"),
    atomically: true,
    encoding: .utf8
  )
  let request = try requestInfo.request(for: URL(fileURLWithPath: "/input.swift"))
  try request.write(
    to: bundlePath.appendingPathComponent("request.json"),
    atomically: true,
    encoding: .utf8
  )
  for compilerArg in requestInfo.compilerArgs {
    // Copy all files from the compiler arguments into the reproducer bundle.
    // Don't include files in Xcode (.app), Xcode toolchains or usr because they are most likely binary files that aren't user specific and would bloat the reproducer bundle.
    if compilerArg.hasPrefix("/"), !compilerArg.contains(".app"), !compilerArg.contains(".xctoolchain"),
      !compilerArg.contains("/usr/")
    {
      let dest = URL(fileURLWithPath: bundlePath.path + compilerArg)
      try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? FileManager.default.copyItem(at: URL(fileURLWithPath: compilerArg), to: dest)
    }
  }
  return bundlePath
}
