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

import BuildServerProtocol
import LanguageServerProtocol
import TSCBasic
import enum TSCUtility.Platform
import Dispatch

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

  /// Delegate to handle any build system events.
  public weak var delegate: BuildSystemDelegate? = nil

  public var indexStorePath: AbsolutePath? { return nil }

  public var indexDatabasePath: AbsolutePath? { return nil }

  public func settings(for uri: DocumentURI, _ language: Language) -> FileBuildSettings? {
    switch language {
    case .swift:
      return settingsSwift(uri.pseudoPath)
    case .c, .cpp, .objective_c, .objective_cpp:
      return settingsClang(uri.pseudoPath, language)
    default:
      return nil
    }
  }

  public func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
    guard let delegate = self.delegate else { return }

    let settings = self.settings(for: uri, language)
    DispatchQueue.global().async {
      delegate.fileBuildSettingsChanged([uri: FileBuildSettingsChange(settings)])
    }
  }

  /// We don't support change watching.
  public func unregisterForChangeNotifications(for: DocumentURI) {}

  public func buildTargets(reply: @escaping (LSPResult<[BuildTarget]>) -> Void) {
    reply(.failure(buildTargetsNotSupported))
  }

  public func buildTargetSources(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[SourcesItem]>) -> Void) {
    reply(.failure(buildTargetsNotSupported))
  }

  public func buildTargetOutputPaths(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[OutputsItem]>) -> Void) {
    reply(.failure(buildTargetsNotSupported))
  }

  func settingsSwift(_ file: String) -> FileBuildSettings {
    var args: [String] = []
    if let sdkpath = sdkpath {
      args += [
        "-sdk",
        sdkpath.pathString,
      ]
    }
    args.append(file)
    return FileBuildSettings(compilerArguments: args)
  }

  func settingsClang(_ file: String, _ language: Language) -> FileBuildSettings {
    var args: [String] = []
    if let sdkpath = sdkpath {
      args += [
        "-isysroot",
        sdkpath.pathString,
      ]
    }
    args.append(file)
    return FileBuildSettings(compilerArguments: args)
  }
}
