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

import TSCBasic
import LanguageServerProtocol

/// Provides build settings from a list of build systems in priority order.
public final class BuildSystemList {

  /// The build systems to try (in order).
  public var providers: [BuildSystem] = [
    FallbackBuildSystem()
  ]

  public init() {}
}

extension BuildSystemList: BuildSystem {

  public var indexStorePath: AbsolutePath? { return providers.first?.indexStorePath }

  public var indexDatabasePath: AbsolutePath? { return providers.first?.indexDatabasePath }

  public func settings(for url: URL, _ language: Language) -> FileBuildSettings? {
    for provider in providers {
      if let settings = provider.settings(for: url, language) {
        return settings
      }
    }
    return nil
  }

  public func toolchain(for url: URL, _ language: Language) -> Toolchain? {
    return providers.first?.toolchain(for: url, language)
  }
}
