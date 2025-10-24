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

@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) package import SKLogging
import SwiftExtensions

// MARK: - Build settings logger

/// Shared logger that only logs build settings for a file once unless they change
package actor BuildSettingsLogger {
  private var loggedSettings: [DocumentURI: FileBuildSettings] = [:]

  package func log(level: LogLevel = .default, settings: FileBuildSettings, for uri: DocumentURI) {
    guard loggedSettings[uri] != settings else {
      return
    }
    loggedSettings[uri] = settings
    Self.log(level: level, settings: settings, for: uri)
  }

  /// Log the given build settings for a single file
  ///
  /// In contrast to the instance method `log`, this will always log the build settings. The instance method only logs
  /// the build settings if they have changed.
  package static func log(level: LogLevel = .default, settings: FileBuildSettings, for uri: DocumentURI) {
    log(level: level, settings: settings, for: [uri])
  }

  /// Log the given build settings for a list of source files that all share the same build settings.
  ///
  /// In contrast to the instance method `log`, this will always log the build settings. The instance method only logs
  /// the build settings if they have changed.
  package static func log(level: LogLevel = .default, settings: FileBuildSettings, for uris: [DocumentURI]) {
    let header: String
    if let uri = uris.only {
      header = "Build settings for \(uri.forLogging)"
    } else if let firstUri = uris.first {
      header = "Build settings for \(firstUri.forLogging) and \(uris.count - 1) others"
    } else {
      header = "Build settings for empty list"
    }
    log(level: level, settings: settings, header: header)
  }

  private static func log(level: LogLevel = .default, settings: FileBuildSettings, header: String) {
    let log = """
      Compiler Arguments:
      \(settings.compilerArguments.joined(separator: "\n"))

      Working directory:
      \(settings.workingDirectory ?? "<nil>")
      """

    let chunks = splitLongMultilineMessage(message: log)
    // Only print the first 100 chunks. If the argument list gets any longer, we don't want to spam the log too much.
    // In practice, 100 chunks should be sufficient.
    for (index, chunk) in chunks.enumerated().prefix(100) {
      logger.log(
        level: level,
        """
        \(header) (\(index + 1)/\(chunks.count))
        \(chunk)
        """
      )
    }
  }
}
