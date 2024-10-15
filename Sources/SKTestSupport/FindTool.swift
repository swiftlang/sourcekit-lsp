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

#if compiler(>=6)
package import Foundation

import class TSCBasic.Process
#else
import Foundation

import class TSCBasic.Process
#endif

#if os(Windows)
import WinSDK
#endif

// Returns the path to the given tool, as found by `xcrun --find` on macOS, or `which` on Linux.
package func findTool(name: String) async -> URL? {
  #if os(macOS)
  let cmd = ["/usr/bin/xcrun", "--find", name]
  #elseif os(Windows)
  var buf = [WCHAR](repeating: 0, count: Int(MAX_PATH))
  GetWindowsDirectoryW(&buf, DWORD(MAX_PATH))
  let wherePath = String(decodingCString: &buf, as: UTF16.self)
    .appendingPathComponent("system32")
    .appendingPathComponent("where.exe")
  let cmd = [wherePath, name]
  #elseif os(Android)
  let cmd = ["/system/bin/which", name]
  #else
  let cmd = ["/usr/bin/which", name]
  #endif

  guard let result = try? await Process.run(arguments: cmd, workingDirectory: nil) else {
    return nil
  }
  guard var path = try? String(bytes: result.output.get(), encoding: .utf8) else {
    return nil
  }
  #if os(Windows)
  // where.exe returns all files that match the name. We only care about the first one.
  if let newlineIndex = path.firstIndex(where: \.isNewline) {
    path = String(path[..<newlineIndex])
  }
  #endif
  path = path.trimmingCharacters(in: .whitespacesAndNewlines)
  if path.isEmpty {
    return nil
  }
  return URL(fileURLWithPath: path, isDirectory: false)
}
