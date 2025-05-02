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

/// An experimental feature that can be enabled by passing `--experimental-feature`
/// to `sourcekit-lsp` on the command line or through the configuration file.
/// The raw value of this feature is how it is named on the command line and in the configuration file.
public enum ExperimentalFeature: String, Codable, Sendable, CaseIterable {
  /// Enable support for the `textDocument/onTypeFormatting` request.
  case onTypeFormatting = "on-type-formatting"

  /// Enable support for the `workspace/_setOptions` request.
  ///
  /// - Note: Internal option
  case setOptionsRequest = "set-options-request"

  /// Enable the `workspace/_sourceKitOptions` request.
  ///
  /// - Note: Internal option
  case sourceKitOptionsRequest = "sourcekit-options-request"

  /// Enable the `sourceKit/_isIndexing` request.
  ///
  /// - Note: Internal option
  case isIndexingRequest = "is-indexing-request"

  /// Indicate that the client can handle the experimental `structure` field in the `window/logMessage` notification.
  case structuredLogs = "structured-logs"

  /// Enable the `workspace/_outputPaths` request.
  ///
  /// - Note: Internal option
  case outputPathsRequest = "output-paths-request"

  /// Enable the `buildServerUpdates` option in the `workspace/synchronize` request.
  ///
  /// - Note: Internal option, for testing only
  case synchronizeForBuildSystemUpdates = "synchronize-for-build-system-updates"

  /// All non-internal experimental features.
  public static var allNonInternalCases: [ExperimentalFeature] {
    allCases.filter { !$0.isInternal }
  }

  /// Whether the feature is internal.
  var isInternal: Bool {
    switch self {
    case .onTypeFormatting:
      return false
    case .setOptionsRequest:
      return true
    case .sourceKitOptionsRequest:
      return true
    case .isIndexingRequest:
      return true
    case .structuredLogs:
      return false
    case .outputPathsRequest:
      return true
    case .synchronizeForBuildSystemUpdates:
      return true
    }
  }
}
