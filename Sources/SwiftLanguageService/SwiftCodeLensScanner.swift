//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftSyntax

/// Scans a source file for classes or structs annotated with `@main` and returns a code lens for them.
final class SwiftCodeLensScanner: SyntaxVisitor {
  /// The document snapshot of the syntax tree that is being walked.
  private let snapshot: DocumentSnapshot

  /// The collection of CodeLenses found in the document.
  private var result: [CodeLens] = []

  private let targetName: String?

  /// The map of supported commands and their client side command names
  private let supportedCommands: [SupportedCodeLensCommand: String]

  private init(
    snapshot: DocumentSnapshot,
    targetName: String?,
    supportedCommands: [SupportedCodeLensCommand: String]
  ) {
    self.snapshot = snapshot
    self.targetName = targetName
    self.supportedCommands = supportedCommands
    super.init(viewMode: .fixedUp)
  }

  /// Public entry point. Scans the syntax tree of the given snapshot for an `@main` annotation
  /// and returns CodeLens's with Commands to run/debug the application.
  public static func findCodeLenses(
    in snapshot: DocumentSnapshot,
    syntaxTreeManager: SyntaxTreeManager,
    targetName: String? = nil,
    supportedCommands: [SupportedCodeLensCommand: String]
  ) async -> [CodeLens] {
    guard snapshot.text.contains("@main") && !supportedCommands.isEmpty else {
      // This is intended to filter out files that obviously do not contain an entry point.
      return []
    }

    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let visitor = SwiftCodeLensScanner(snapshot: snapshot, targetName: targetName, supportedCommands: supportedCommands)
    visitor.walk(syntaxTree)
    return visitor.result
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    node.attributes.forEach(self.captureLensFromAttribute)
    return .skipChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    node.attributes.forEach(self.captureLensFromAttribute)
    return .skipChildren
  }

  private func captureLensFromAttribute(attribute: AttributeListSyntax.Element) {
    if attribute.trimmedDescription == "@main" {
      let range = self.snapshot.absolutePositionRange(of: attribute.trimmedRange)
      var targetNameToAppend: String = ""
      var arguments: [LSPAny] = []
      if let targetName {
        targetNameToAppend = " \(targetName)"
        arguments.append(.string(targetName))
      }

      if let runCommand = supportedCommands[SupportedCodeLensCommand.run] {
        // Return commands for running/debugging the executable.
        // These command names must be recognized by the client and so should not be chosen arbitrarily.
        self.result.append(
          CodeLens(
            range: range,
            command: Command(title: "Run" + targetNameToAppend, command: runCommand, arguments: arguments)
          )
        )
      }

      if let debugCommand = supportedCommands[SupportedCodeLensCommand.debug] {
        self.result.append(
          CodeLens(
            range: range,
            command: Command(title: "Debug" + targetNameToAppend, command: debugCommand, arguments: arguments)
          )
        )
      }
    }
  }
}
