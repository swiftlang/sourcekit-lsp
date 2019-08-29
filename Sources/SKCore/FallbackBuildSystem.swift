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

import LanguageServerProtocol
import TSCBasic
import enum TSCUtility.Platform

/// A simple BuildSystem suitable as a fallback when accurate settings are unknown.
public final class FallbackBuildSystem: BuildSystem {

  public init() {}

  /// The path to the SDK.
  public lazy var sdkpath: AbsolutePath? = {
    if case .darwin? = Platform.currentPlatform,
       let str = try? Process.checkNonZeroExit(
         args: "/usr/bin/xcrun", "--show-sdk-path", "--sdk", "macosx"),
       let path = try? AbsolutePath(validating: str.spm_chomp())
    {
      return path
    }
    return nil
  }()

  public var indexStorePath: AbsolutePath? { return nil }

  public var indexDatabasePath: AbsolutePath? { return nil }

  public func settings(for url: URL, _ language: Language) -> FileBuildSettings? {
    guard let path = try? AbsolutePath(validating: url.path) else {
      return nil
    }

    switch language {
    case .swift:
      return settingsSwift(path)
    case .c, .cpp, .objective_c, .objective_cpp:
      return settingsClang(path, language)
    default:
      return nil
    }
  }

  public func toolchain(for: URL, _ language: Language) -> Toolchain? { return nil }

  func settingsSwift(_ path: AbsolutePath) -> FileBuildSettings {
    var args: [String] = []
    if let sdkpath = sdkpath {
      args += [
        "-sdk",
        sdkpath.pathString,
      ]
    }
    args.append(path.pathString)
    return FileBuildSettings(compilerArguments: args)
  }

  func settingsClang(_ path: AbsolutePath, _ language: Language) -> FileBuildSettings {
    var args: [String] = []
    if let sdkpath = sdkpath {
      args += [
        "-isysroot",
        sdkpath.pathString,
      ]
    }
    args.append(path.pathString)
    return FileBuildSettings(compilerArguments: args)
  }
}
