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

import Foundation

import class TSCBasic.Process
import struct TSCBasic.AbsolutePath
import var TSCBasic.localFileSystem

private func isAndroid() -> Bool {
  return (try? localFileSystem.isFile(AbsolutePath(validating: "/system/bin/toolchain"))) ?? false ||
      (try? localFileSystem.isFile(AbsolutePath(validating: "/system/bin/toybox"))) ?? false
}

public enum Platform: Equatable {
  case android
  case darwin
  case linux
  case windows
}

extension Platform {
  // This is not just a computed property because the ToolchainRegistryTests
  // change the value.
  public static var current: Platform? = {
    #if os(Windows)
    return .windows
    #else
    switch try? Process.checkNonZeroExit(args: "uname")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() {
    case "darwin"?:
      return .darwin
    case "linux"?:
      return isAndroid() ? .android : .linux
    default:
      return nil
    }
    #endif
  }()
}

extension Platform {
  /// The file extension used for a dynamic library on this platform.
  public var dynamicLibraryExtension: String {
    switch self {
    case .darwin: return ".dylib"
    case .linux, .android: return ".so"
    case .windows: return ".dll"
    }
  }

  public var executableExtension: String {
    switch self {
    case .windows: return ".exe"
    case .linux, .android, .darwin: return ""
    }
  }
}
