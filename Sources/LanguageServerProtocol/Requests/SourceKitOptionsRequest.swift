//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request from the client to the server to retrieve the compiler arguments that SourceKit-LSP uses to process the
/// document.
///
/// This request does not require the document to be opened in SourceKit-LSP. This is also why it has the `workspace/`
/// instead of the `textDocument/` prefix.
///
/// **(LSP Extension)**.
public struct SourceKitOptionsRequest: RequestType, Hashable {
  public static let method: String = "textDocument/sourceKitOptions"
  public typealias Response = SourceKitOptionsResponse?

  /// The document to get options for
  public var textDocument: TextDocumentIdentifier

  /// If set to `true` and build settings could not be determined within a timeout (see `buildSettingsTimeout` in the
  /// SourceKit-LSP configuration file), this request returns fallback build settings.
  ///
  /// If set to `false` the request only finishes when build settings were provided by the build system.
  public var allowFallbackSettings: Bool

  public init(textDocument: TextDocumentIdentifier, allowFallbackSettings: Bool) {
    self.textDocument = textDocument
    self.allowFallbackSettings = allowFallbackSettings
  }
}

public struct SourceKitOptionsResponse: ResponseType, Hashable {
  /// The compiler options required for the requested file.
  public var compilerArguments: [String]

  /// The working directory for the compile command.
  public var workingDirectory: String?

  public init(compilerArguments: [String], workingDirectory: String? = nil) {
    self.compilerArguments = compilerArguments
    self.workingDirectory = workingDirectory
  }
}
