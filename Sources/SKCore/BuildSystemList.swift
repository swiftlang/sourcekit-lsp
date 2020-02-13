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

import TSCBasic
import BuildServerProtocol
import LanguageServerProtocol

/// Provides build settings from a list of build systems in priority order.
public final class BuildSystemList {

  /// Delegate to handle any build system events.
  public var delegate: BuildSystemDelegate? {
    get { return providers.first?.delegate }
    set { providers.first?.delegate = newValue }
  }

  /// The build systems to try (in order).
  public var providers: [BuildSystem] = [
    FallbackBuildSystem()
  ]

  public init() {}
}

extension BuildSystemList: BuildSystem {
  public var indexStorePath: AbsolutePath? { return providers.first?.indexStorePath }

  public var indexDatabasePath: AbsolutePath? { return providers.first?.indexDatabasePath }

  public func settings(for uri: DocumentURI, _ language: Language) -> FileBuildSettings? {
    for provider in providers {
      if let settings = provider.settings(for: uri, language) {
        return settings
      }
    }
    return nil
  }

  /// Register the given file for build-system level change notifications, such as command
  /// line flag changes, dependency changes, etc.
  public func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
    // Only register with the primary build system, since we only use its delegate.
    providers.first?.registerForChangeNotifications(for: uri, language: language)
  }

  /// Unregister the given file for build-system level change notifications, such as command
  /// line flag changes, dependency changes, etc.
  public func unregisterForChangeNotifications(for uri: DocumentURI) {
    // Only unregister with the primary build system, since we only use its delegate.
    providers.first?.unregisterForChangeNotifications(for: uri)
  }

  public func buildTargets(reply: @escaping (LSPResult<[BuildTarget]>) -> Void) {
    providers.first?.buildTargets(reply: reply)
  }

  public func buildTargetSources(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[SourcesItem]>) -> Void) {
    providers.first?.buildTargetSources(targets: targets, reply: reply)
  }

  public func buildTargetOutputPaths(targets: [BuildTargetIdentifier], reply: @escaping (LSPResult<[OutputsItem]>) -> Void) {
    providers.first?.buildTargetOutputPaths(targets: targets, reply: reply)
  }
}
