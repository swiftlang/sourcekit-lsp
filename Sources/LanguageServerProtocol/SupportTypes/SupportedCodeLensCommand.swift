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

/// Code lenses that LSP can annotate code with.
///
/// Clients provide these as keys to the `supportedCommands` dictionary supplied
/// in the client's `InitializeRequest`.
public struct SupportedCodeLensCommand: Codable, Hashable, RawRepresentable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Lens to run the application
  public static let run: Self = Self(rawValue: "swift.run")

  /// Lens to debug the application
  public static let debug: Self = Self(rawValue: "swift.debug")
}
