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

/// An event describing a file change.
public protocol RegistrationOptions: Codable, LSPAnyCodable, Hashable {
}

/// General text document registration options.
public struct TextDocumentRegistrationOptions: RegistrationOptions {
  /// A document selector to identify the scope of the registration. If not set,
  /// the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  public init(documentSelector: DocumentSelector? = nil) {
    self.documentSelector = documentSelector
  }

  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard let selectorValue = dictionary[CodingKeys.documentSelector.stringValue] else {
      self.documentSelector = nil
      return
    }
    guard case .dictionary(let selectorDictionary) = selectorValue else { return nil }
    guard let documentSelector = DocumentSelector(fromLSPDictionary: selectorDictionary) else {
      return nil
    }
    self.documentSelector = documentSelector
  }

  public func encodeToLSPAny() -> LSPAny {
    guard let documentSelector = documentSelector else { return .dictionary([:]) }
    return .dictionary([CodingKeys.documentSelector.stringValue: documentSelector.encodeToLSPAny()])
  }
}

/// Describe options to be used when registering for file system change events.
public struct DidChangeWatchedFilesRegistrationOptions: RegistrationOptions {
  /// The watchers to register.
  public var watchers: [FileSystemWatcher]

  public init(watchers: [FileSystemWatcher]) {
    self.watchers = watchers
  }

  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard let watchersLSPAny = dictionary[CodingKeys.watchers.stringValue] else { return nil }
    guard let watchers = [FileSystemWatcher].init(fromLSPArray: watchersLSPAny) else { return nil }
    self.watchers = watchers
  }

  public func encodeToLSPAny() -> LSPAny {
    return .dictionary([CodingKeys.watchers.stringValue: watchers.encodeToLSPAny()])
  }
}

/// Execute command registration options.
public struct ExecuteCommandRegistrationOptions: RegistrationOptions {
  /// The commands to be executed on this server.
  public var commands: [String]

  public init(commands: [String]) {
    self.commands = commands
  }

  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard case .array(let commandsArray) = dictionary[CodingKeys.commands.stringValue] else {
      return nil
    }
    var values = [String]()
    values.reserveCapacity(commandsArray.count)
    for lspAny in commandsArray {
      guard case .string(let value) = lspAny else { return nil }
      values.append(value)
    }
    self.commands = values
  }

  public func encodeToLSPAny() -> LSPAny {
    var values = [LSPAny]()
    values.reserveCapacity(commands.count)
    for command in commands {
      values.append(.string(command))
    }
    return .dictionary([CodingKeys.commands.stringValue: .array(values)])
  }
}
