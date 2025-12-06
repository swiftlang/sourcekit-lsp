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

internal import BuildServerIntegration
import BuildServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftSyntax
import ToolchainRegistry

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
    workspace: Workspace?,
    syntaxTreeManager: SyntaxTreeManager,
    supportedCommands: [SupportedCodeLensCommand: String],
    toolchain: Toolchain
  ) async -> [CodeLens] {
    guard !supportedCommands.isEmpty else {
      return []
    }

    var targetDisplayName: String? = nil
    if let workspace,
      let target = await workspace.buildServerManager.canonicalTarget(for: snapshot.uri),
      let buildTarget = await workspace.buildServerManager.buildTarget(named: target)
    {
      targetDisplayName = buildTarget.displayName
    }

    var codeLenses: [CodeLens] = []
    if snapshot.text.contains("@main") {
      let visitor = SwiftCodeLensScanner(
        snapshot: snapshot,
        targetName: targetDisplayName,
        supportedCommands: supportedCommands
      )
      let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
      visitor.walk(syntaxTree)
      codeLenses += visitor.result
    }

    // "swift.play" CodeLens should be ignored if "swift-play" is not in the toolchain as the client has no way of running
    if toolchain.swiftPlay != nil,
      let workspace,
      let playCommand = supportedCommands[SupportedCodeLensCommand.play]
    {
      let playgrounds = await SwiftPlaygroundsScanner.findDocumentPlaygrounds(
        for: snapshot,
        workspace: workspace,
        syntaxTreeManager: syntaxTreeManager
      )
      codeLenses += playgrounds.map({
        CodeLens(
          range: $0.range,
          command: Command(
            title: "Play \"\($0.label ?? $0.id)\"",
            command: playCommand,
            arguments: [$0.encodeToLSPAny()]
          )
        )
      })
    }

    return codeLenses
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
