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

/// FIXME: Find a way to abstract this without deserializing.
/// Maybe use `LSPAnyCodable`?
public func toLSPAny<R: RegistrationOptions>(options: R) throws -> LSPAny {
  let json = try JSONEncoder().encode(options)
  return try JSONDecoder().decode(LSPAny.self, from: json)
}

/// An event describing a file change.
public protocol RegistrationOptions: Codable, Hashable {
}

/// General text document registration options.
public struct TextDocumentRegistrationOptions: RegistrationOptions {
  /// A document selector to identify the scope of the registration. If not set,
  /// the document selector provided on the client side will be used.
  public var documentSelector: DocumentSelector?

  public init(documentSelector: DocumentSelector? = nil) {
    self.documentSelector = documentSelector
  }
}

/// Describe options to be used when registering for file system change events.
public struct DidChangeWatchedFilesRegistrationOptions: RegistrationOptions {
  /// The watchers to register.
  public var watchers: [FileSystemWatcher]

  public init(watchers: [FileSystemWatcher]) {
    self.watchers = watchers
  }
}

/// Execute command registration options.
public struct ExecuteCommandRegistrationOptions: RegistrationOptions {
  /// The commands to be executed on this server.
  public var commands: [String]

  public init(commands: [String]) {
    self.commands = commands
  }
}
