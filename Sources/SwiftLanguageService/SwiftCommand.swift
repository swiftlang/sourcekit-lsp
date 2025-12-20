//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) package import LanguageServerProtocol

/// A `Command` that should be executed by Swift's language server.
package protocol SwiftCommand: Codable, Hashable, LSPAnyCodable {
  static var identifier: String { get }
  var title: String { get set }
}

extension SwiftCommand {
  /// Converts this `SwiftCommand` to a generic LSP `Command` object.
  package func asCommand() -> Command {
    let argument = encodeToLSPAny()
    return Command(title: title, command: Self.identifier, arguments: [argument])
  }
}

extension ExecuteCommandRequest {
  /// Attempts to convert the underlying `Command` metadata from this request
  /// to a specific Swift language server `SwiftCommand`.
  ///
  /// - Parameters:
  ///   - type: The `SwiftCommand` metatype to convert to.
  package func swiftCommand<T: SwiftCommand>(ofType type: T.Type) -> T? {
    guard type.identifier == command else {
      return nil
    }
    guard let argument = arguments?.first else {
      return nil
    }
    guard case let .dictionary(dictionary) = argument else {
      return nil
    }
    return type.init(fromLSPDictionary: dictionary)
  }
}

extension SwiftLanguageService {
  package static var builtInCommands: [String] {
    [
      SemanticRefactorCommand.self,
      ExpandMacroCommand.self,
    ].map { (command: any SwiftCommand.Type) in
      command.identifier
    } + ["objective-c.add.method.implementation"]
  }
}
