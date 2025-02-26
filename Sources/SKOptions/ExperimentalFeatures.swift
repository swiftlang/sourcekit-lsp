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
  case setOptionsRequest = "set-options-request"

  /// Enable the `workspace/_sourceKitOptions` request.
  case sourceKitOptionsRequest = "sourcekit-options-request"
}
