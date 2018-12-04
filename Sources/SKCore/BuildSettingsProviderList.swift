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

/// Provides build settings from a list of providers in priority order.
public final class BuildSettingsProviderList: BuildSystem {

  /// The build settings providers to try (in order).
  public var providers: [BuildSystem] = [
    FallbackBuildSettingsProvider()
  ]

  public init() {}

  public func settings(for url: URL, _ language: Language) -> FileBuildSettings? {
    for provider in providers {
      if let settings = provider.settings(for: url, language) {
        return settings
      }
    }
    return nil
  }
}
