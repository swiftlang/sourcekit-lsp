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
public protocol RegistrationOptions: Hashable {
  func encodeIntoLSPAny(dict: inout [String: LSPAny])
}

fileprivate func encode(strings: [String]) -> LSPAny {
  var values = [LSPAny]()
  values.reserveCapacity(strings.count)
  for str in strings {
    values.append(.string(str))
  }
  return .array(values)
}

/// General text document registration options.
public class TextDocumentRegistrationOptions: RegistrationOptions, Hashable {
  /// A document selector to identify the scope of the registration. If not set,
  /// the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  public init(documentSelector: DocumentSelector? = nil) {
    self.documentSelector = documentSelector
  }

  public func encodeIntoLSPAny(dict: inout [String: LSPAny]) {
    guard let documentSelector = documentSelector else { return }
    dict["documentSelector"] = documentSelector.encodeToLSPAny()
  }

  public static func == (lhs: TextDocumentRegistrationOptions, rhs: TextDocumentRegistrationOptions) -> Bool {
    return lhs.documentSelector == rhs.documentSelector
  }

  public func hash(into hasher: inout Hasher) {
    documentSelector?.hash(into: &hasher)
  }
}

/// Code completiion registration options.
public class CompletionRegistrationOptions: TextDocumentRegistrationOptions {
  public var completionOptions: CompletionOptions

  public init(documentSelector: DocumentSelector? = nil, completionOptions: CompletionOptions) {
    self.completionOptions = completionOptions
    super.init(documentSelector: documentSelector)
  }

  public override func encodeIntoLSPAny(dict: inout [String: LSPAny]) {
    super.encodeIntoLSPAny(dict: &dict)
    if let resolveProvider = completionOptions.resolveProvider {
      dict["resolveProvider"] = .bool(resolveProvider)
    }
    if let triggerCharacters = completionOptions.triggerCharacters {
      dict["triggerCharacters"] = encode(strings: triggerCharacters)
    }
    if let allCommitCharacters = completionOptions.allCommitCharacters {
      dict["allCommitCharacters"] = encode(strings: allCommitCharacters)
    }
  }

  public static func == (lhs: CompletionRegistrationOptions, rhs: CompletionRegistrationOptions) -> Bool {
    return lhs.documentSelector == rhs.documentSelector && lhs.completionOptions == rhs.completionOptions
  }

  public override func hash(into hasher: inout Hasher) {
    super.hash(into: &hasher)
    completionOptions.hash(into: &hasher)
  }
}

/// Describe options to be used when registering for file system change events.
public struct DidChangeWatchedFilesRegistrationOptions: RegistrationOptions {
  /// The watchers to register.
  public var watchers: [FileSystemWatcher]

  public init(watchers: [FileSystemWatcher]) {
    self.watchers = watchers
  }

  public func encodeIntoLSPAny(dict: inout [String: LSPAny]) {
    dict["watchers"] = watchers.encodeToLSPAny()
  }
}

/// Execute command registration options.
public struct ExecuteCommandRegistrationOptions: RegistrationOptions {
  /// The commands to be executed on this server.
  public var commands: [String]

  public init(commands: [String]) {
    self.commands = commands
  }

  public func encodeIntoLSPAny(dict: inout [String: LSPAny]) {
    dict["commands"] = encode(strings: commands)
  }
}
