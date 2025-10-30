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
public struct SourceKitOptionsRequest: LSPRequest, Hashable {
  public static let method: String = "workspace/_sourceKitOptions"
  public typealias Response = SourceKitOptionsResponse

  /// The document to get options for
  public var textDocument: TextDocumentIdentifier

  /// If specified, explicitly request the compiler arguments when interpreting the document in the context of the given
  /// target.
  ///
  /// The target URI must match the URI that is used by the BSP server to identify the target. This option thus only
  /// makes sense to specify if the client also controls the BSP server.
  ///
  /// When this is `nil`, SourceKit-LSP returns the compiler arguments it uses when the the document is opened in the
  /// client, ie. it infers a canonical target for the document.
  public var target: DocumentURI?

  /// Whether SourceKit-LSP should ensure that the document's target is prepared before returning build settings.
  ///
  /// There is a tradeoff whether the target should be prepared: Preparing a target may take significant time but if the
  /// target is not prepared, the build settings might eg. refer to modules that haven't been built yet.
  public var prepareTarget: Bool

  /// If set to `true` and build settings could not be determined within a timeout (see `buildSettingsTimeout` in the
  /// SourceKit-LSP configuration file), this request returns fallback build settings.
  ///
  /// If set to `false` the request only finishes when build settings were provided by the build server.
  public var allowFallbackSettings: Bool

  public init(
    textDocument: TextDocumentIdentifier,
    target: DocumentURI? = nil,
    prepareTarget: Bool,
    allowFallbackSettings: Bool
  ) {
    self.textDocument = textDocument
    self.target = target
    self.prepareTarget = prepareTarget
    self.allowFallbackSettings = allowFallbackSettings
  }
}

/// The kind of options that were returned by the `workspace/_sourceKitOptions` request, ie. whether they are fallback
/// options or the real compiler options for the file.
public struct SourceKitOptionsKind: RawRepresentable, Codable, Hashable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// The SourceKit options are known to SourceKit-LSP and returned them.
  public static let normal = SourceKitOptionsKind(rawValue: "normal")

  /// SourceKit-LSP was unable to determine the build settings for this file and synthesized fallback settings.
  public static let fallback = SourceKitOptionsKind(rawValue: "fallback")
}

public struct SourceKitOptionsResponse: ResponseType, Hashable {
  /// The compiler options required for the requested file.
  public var compilerArguments: [String]

  /// The working directory for the compile command.
  public var workingDirectory: String?

  /// Whether SourceKit-LSP was able to determine the build settings or synthesized fallback settings.
  public var kind: SourceKitOptionsKind

  /// - `true` If the request requested the file's target to be prepared and the target needed preparing
  /// - `false` If the request requested the file's target to be prepared and the target was up to date
  /// - `nil`: If the request did not request the file's target to be prepared or the target  could not be prepared for
  ///    other reasons
  public var didPrepareTarget: Bool?

  /// Additional data that the BSP server returned in the `textDocument/sourceKitOptions` BSP request. This data is not
  /// interpreted by SourceKit-LSP.
  public var data: LSPAny?

  public init(
    compilerArguments: [String],
    workingDirectory: String? = nil,
    kind: SourceKitOptionsKind,
    didPrepareTarget: Bool? = nil,
    data: LSPAny? = nil
  ) {
    self.compilerArguments = compilerArguments
    self.workingDirectory = workingDirectory
    self.kind = kind
    self.didPrepareTarget = didPrepareTarget
    self.data = data
  }
}
