//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// Protocol for capability registration options, which must be encodable to
/// `LSPAny` so they can be included in a `Registration`.
public protocol RegistrationOptions: Hashable, LSPAnyCodable {

}

/// General text document registration options.
public struct TextDocumentRegistrationOptions: RegistrationOptions, Hashable {
  /// A document selector to identify the scope of the registration. If not set,
  /// the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  public init(documentSelector: DocumentSelector? = nil) {
    self.documentSelector = documentSelector
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    if let value = dictionary["documentSelector"] {
      self.documentSelector = DocumentSelector(fromLSPArray: value)
    } else {
      self.documentSelector = nil
    }
  }

  public func encodeToLSPAny() -> LSPAny {
    guard let documentSelector = documentSelector else {
      return .dictionary([:])
    }

    return .dictionary(["documentSelector": documentSelector.encodeToLSPAny()])
  }
}

/// Protocol for a type which structurally represents`TextDocumentRegistrationOptions`.
public protocol TextDocumentRegistrationOptionsProtocol {
  var textDocumentRegistrationOptions: TextDocumentRegistrationOptions { get }
}

/// Code completiion registration options.
public struct CompletionRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol, Hashable {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var completionOptions: CompletionOptions

  public init(documentSelector: DocumentSelector? = nil, completionOptions: CompletionOptions) {
    self.textDocumentRegistrationOptions =
      TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.completionOptions = completionOptions
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard let completionOptions = CompletionOptions(fromLSPDictionary: dictionary) else {
      return nil
    }

    self.completionOptions = completionOptions

    guard let textDocumentRegistrationOptions = TextDocumentRegistrationOptions(fromLSPDictionary: dictionary) else {
      return nil
    }

    self.textDocumentRegistrationOptions = textDocumentRegistrationOptions
  }

  public func encodeToLSPAny() -> LSPAny {
    var dict: [String: LSPAny] = [:]

    if case .dictionary(let dictionary) = completionOptions.encodeToLSPAny() {
      dict.merge(dictionary) { (current, _) in current }
    }

    if case .dictionary(let dictionary) = textDocumentRegistrationOptions.encodeToLSPAny() {
      dict.merge(dictionary) { (current, _) in current }
    }

    return .dictionary(dict)
  }
}

/// Folding range registration options.
public struct FoldingRangeRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol, Hashable {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var foldingRangeOptions: FoldingRangeOptions

  public init(documentSelector: DocumentSelector? = nil, foldingRangeOptions: FoldingRangeOptions) {
    self.textDocumentRegistrationOptions =
      TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.foldingRangeOptions = foldingRangeOptions
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard let textDocumentRegistrationOptions = TextDocumentRegistrationOptions(fromLSPDictionary: dictionary) else {
      return nil
    }

    self.textDocumentRegistrationOptions = textDocumentRegistrationOptions

    /// Currently empty in the spec.
    self.foldingRangeOptions = FoldingRangeOptions()
  }

  public func encodeToLSPAny() -> LSPAny {
    textDocumentRegistrationOptions.encodeToLSPAny()
    // foldingRangeOptions is currently empty.
  }
}

public struct SemanticTokensRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol, Hashable
{
  /// Method for registration, which defers from the actual requests' methods
  /// since this registration handles multiple requests.
  public static let method: String = "textDocument/semanticTokens"

  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var semanticTokenOptions: SemanticTokensOptions

  public init(documentSelector: DocumentSelector? = nil, semanticTokenOptions: SemanticTokensOptions) {
    self.textDocumentRegistrationOptions =
      TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.semanticTokenOptions = semanticTokenOptions
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard let textDocumentRegistrationOptions = TextDocumentRegistrationOptions(fromLSPDictionary: dictionary) else {
      return nil
    }

    self.textDocumentRegistrationOptions = textDocumentRegistrationOptions

    guard let semanticTokenOptions = SemanticTokensOptions(fromLSPDictionary: dictionary) else {
      return nil
    }

    self.semanticTokenOptions = semanticTokenOptions
  }

  public func encodeToLSPAny() -> LSPAny {
    var dict: [String: LSPAny] = [:]

    if case .dictionary(let dictionary) = textDocumentRegistrationOptions.encodeToLSPAny() {
      dict.merge(dictionary) { (current, _) in current }
    }

    if case .dictionary(let dictionary) = semanticTokenOptions.encodeToLSPAny() {
      dict.merge(dictionary) { (current, _) in current }
    }

    return .dictionary(dict)
  }
}

public struct InlayHintRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol, Hashable {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var inlayHintOptions: InlayHintOptions

  public init(
    documentSelector: DocumentSelector? = nil,
    inlayHintOptions: InlayHintOptions
  ) {
    textDocumentRegistrationOptions = TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.inlayHintOptions = inlayHintOptions
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    self.inlayHintOptions = InlayHintOptions()

    if case .bool(let resolveProvider) = dictionary["resolveProvider"] {
      self.inlayHintOptions.resolveProvider = resolveProvider
    }

    guard let textDocumentRegistrationOptions = TextDocumentRegistrationOptions(fromLSPDictionary: dictionary) else {
      return nil
    }

    self.textDocumentRegistrationOptions = textDocumentRegistrationOptions
  }

  public func encodeToLSPAny() -> LSPAny {
    var dict: [String: LSPAny] = [:]

    if let resolveProvider = inlayHintOptions.resolveProvider {
      dict["resolveProvider"] = .bool(resolveProvider)
    }

    if case .dictionary(let dictionary) = textDocumentRegistrationOptions.encodeToLSPAny() {
      dict.merge(dictionary) { (current, _) in current }
    }

    return .dictionary(dict)
  }
}

/// Describe options to be used when registering for pull diagnostics. Since LSP 3.17.0
public struct DiagnosticRegistrationOptions: RegistrationOptions, TextDocumentRegistrationOptionsProtocol {
  public var textDocumentRegistrationOptions: TextDocumentRegistrationOptions
  public var diagnosticOptions: DiagnosticOptions

  public init(
    documentSelector: DocumentSelector? = nil,
    diagnosticOptions: DiagnosticOptions
  ) {
    textDocumentRegistrationOptions = TextDocumentRegistrationOptions(documentSelector: documentSelector)
    self.diagnosticOptions = diagnosticOptions
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard let textDocumentRegistrationOptions = TextDocumentRegistrationOptions(fromLSPDictionary: dictionary) else {
      return nil
    }

    self.textDocumentRegistrationOptions = textDocumentRegistrationOptions

    guard let diagnosticOptions = DiagnosticOptions(fromLSPDictionary: dictionary) else {
      return nil
    }
    self.diagnosticOptions = diagnosticOptions
  }

  public func encodeToLSPAny() -> LSPAny {
    var dict: [String: LSPAny] = [:]
    if case .dictionary(let dictionary) = textDocumentRegistrationOptions.encodeToLSPAny() {
      dict.merge(dictionary) { (current, _) in current }
    }

    if case .dictionary(let dictionary) = diagnosticOptions.encodeToLSPAny() {
      dict.merge(dictionary) { (current, _) in current }
    }
    return .dictionary(dict)
  }
}

/// Describe options to be used when registering for file system change events.
public struct DidChangeWatchedFilesRegistrationOptions: RegistrationOptions {
  /// The watchers to register.
  public var watchers: [FileSystemWatcher]

  public init(watchers: [FileSystemWatcher]) {
    self.watchers = watchers
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard let watchersArray = dictionary["watchers"],
      let watchers = [FileSystemWatcher](fromLSPArray: watchersArray)
    else {
      return nil
    }

    self.watchers = watchers
  }

  public func encodeToLSPAny() -> LSPAny {
    .dictionary(["watchers": watchers.encodeToLSPAny()])
  }
}

/// Execute command registration options.
public struct ExecuteCommandRegistrationOptions: RegistrationOptions {
  /// The commands to be executed on this server.
  public var commands: [String]

  public init(commands: [String]) {
    self.commands = commands
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    guard let commandsArray = dictionary["commands"],
      let commands = [String](fromLSPArray: commandsArray)
    else {
      return nil
    }

    self.commands = commands
  }

  public func encodeToLSPAny() -> LSPAny {
    .dictionary(["commands": commands.encodeToLSPAny()])
  }
}
