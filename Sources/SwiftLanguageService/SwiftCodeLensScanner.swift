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
internal import IndexStoreDB
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
import SourceKitLSP
import SwiftSyntax
import ToolchainRegistry

/// Scans a source file for code lenses including `@main` run/debug actions,
/// symbol reference counts, and playground entries.
final class SwiftCodeLensScanner: SyntaxVisitor {
  /// The document snapshot of the syntax tree that is being walked.
  private let snapshot: DocumentSnapshot

  /// The collection of CodeLenses found in the document.
  private var result: [CodeLens] = []

  /// The display name of the build target containing this document, if available.
  private let targetName: String?

  /// The language service used to resolve cursor info for symbols.
  private let languageService: SwiftLanguageService

  /// The map of supported commands and their client side command names.
  private let supportedCommands: [SupportedCodeLensCommand: String]

  /// Symbols collected during the syntax walk, processed asynchronously afterward.
  private var symbolsToProcess: [(nameToken: TokenSyntax, displayRange: Range<AbsolutePosition>)] = []

  private let workspace: Workspace?

  private init(
    snapshot: DocumentSnapshot,
    targetName: String?,
    supportedCommands: [SupportedCodeLensCommand: String],
    workspace: Workspace?,
    languageService: SwiftLanguageService
  ) {
    self.snapshot = snapshot
    self.targetName = targetName
    self.supportedCommands = supportedCommands
    self.workspace = workspace
    self.languageService = languageService
    super.init(viewMode: .fixedUp)
  }

  /// Public entry point. Scans the syntax tree of the given snapshot and returns
  /// all applicable code lenses including `@main` run/debug actions, reference counts,
  /// and playground entries.
  public static func findCodeLenses(
    in snapshot: DocumentSnapshot,
    workspace: Workspace?,
    syntaxTreeManager: SyntaxTreeManager,
    supportedCommands: [SupportedCodeLensCommand: String],
    toolchain: Toolchain,
    languageService: SwiftLanguageService
  ) async -> [CodeLens] {
    guard !supportedCommands.isEmpty else {
      return []
    }

    let targetDisplayName = await resolveTargetDisplayName(for: snapshot, workspace: workspace)

    // Process @main annotations and symbol references
    let visitor = SwiftCodeLensScanner(
      snapshot: snapshot,
      targetName: targetDisplayName,
      supportedCommands: supportedCommands,
      workspace: workspace,
      languageService: languageService
    )
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    visitor.walk(syntaxTree)

    // Process collected symbols asynchronously for reference counts
    for (nameToken, displayRange) in visitor.symbolsToProcess {
      await visitor.captureReferenceLens(for: nameToken, at: displayRange)
    }

    var codeLenses = visitor.result

    // Append playground lenses if swift-play is available in the toolchain
    codeLenses += await playgroundLenses(
      for: snapshot,
      workspace: workspace,
      toolchain: toolchain,
      syntaxTreeManager: syntaxTreeManager,
      supportedCommands: supportedCommands
    )

    return codeLenses
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    node.attributes.forEach(captureMainAttributeLens)
    symbolsToProcess.append((nameToken: node.name, displayRange: node.trimmedRange))
    return .visitChildren
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    node.attributes.forEach(captureMainAttributeLens)
    symbolsToProcess.append((nameToken: node.name, displayRange: node.trimmedRange))
    return .visitChildren
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    symbolsToProcess.append((nameToken: node.name, displayRange: node.trimmedRange))
    return .visitChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    node.attributes.forEach(captureMainAttributeLens)
    symbolsToProcess.append((nameToken: node.name, displayRange: node.trimmedRange))
    return .visitChildren
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    symbolsToProcess.append((nameToken: node.name, displayRange: node.trimmedRange))
    return .visitChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    // Only show references for member-level variables, not locals.
    guard node.parent?.is(MemberBlockItemSyntax.self) == true else {
      return .visitChildren
    }
    // Variable declarations can have multiple bindings (e.g., let x = 1, y = 2)
    for binding in node.bindings {
      if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
        symbolsToProcess.append((nameToken: identifier.identifier, displayRange: binding.trimmedRange))
      }
    }
    return .visitChildren
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    symbolsToProcess.append((nameToken: node.name, displayRange: node.trimmedRange))
    return .visitChildren
  }

  override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
    symbolsToProcess.append((nameToken: node.name, displayRange: node.trimmedRange))
    return .visitChildren
  }

  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    symbolsToProcess.append((nameToken: node.initKeyword, displayRange: node.trimmedRange))
    return .visitChildren
  }

  override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
    symbolsToProcess.append((nameToken: node.subscriptKeyword, displayRange: node.trimmedRange))
    return .visitChildren
  }

  /// Adds run and debug code lenses for `@main` attributes.
  private func captureMainAttributeLens(attribute: AttributeListSyntax.Element) {
    guard attribute.trimmedDescription == "@main" else {
      return
    }

    let range = snapshot.absolutePositionRange(of: attribute.trimmedRange)
    let suffix = targetName.map { " \($0)" } ?? ""
    let arguments: [LSPAny] = targetName.map { [.string($0)] } ?? []

    // Return commands for running/debugging the executable.
    // These command names must be recognized by the client and so should not be chosen arbitrarily.
    if let runCommand = supportedCommands[.run] {
      result.append(
        CodeLens(
          range: range,
          command: Command(title: "Run" + suffix, command: runCommand, arguments: arguments)
        )
      )
    }
    if let debugCommand = supportedCommands[.debug] {
      result.append(
        CodeLens(
          range: range,
          command: Command(title: "Debug" + suffix, command: debugCommand, arguments: arguments)
        )
      )
    }
  }

  /// Queries the index for the number of references to a symbol and appends a code lens with the count.
  private func captureReferenceLens(for nameToken: TokenSyntax, at displayRange: Range<AbsolutePosition>) async {
    guard let referencesCommand = supportedCommands[.references] else { return }

    let lensRange = snapshot.absolutePositionRange(of: displayRange)
    let nameRange = snapshot.absolutePositionRange(of: nameToken.trimmedRange)

    do {
      let cursorInfoResults = try await languageService.cursorInfo(
        snapshot,
        compileCommand: await languageService.compileCommand(for: snapshot.uri, fallbackAfterTimeout: false),
        nameRange
      )
      .cursorInfo

      guard let cursorInfo = cursorInfoResults.first,
        let usr = cursorInfo.symbolInfo.usr,
        let index = await workspace?.index(checkedFor: .deletedFiles)
      else { return }

      var referenceCount = 0
      index.forEachSymbolOccurrence(byUSR: usr, roles: .reference) { _ in
        referenceCount += 1
        return true
      }

      let title = "\(referenceCount) reference\(referenceCount == 1 ? "" : "s")"
      result.append(
        CodeLens(
          range: lensRange,
          command: Command(
            title: title,
            command: referencesCommand,
            arguments: [.string(snapshot.uri.stringValue), nameRange.lowerBound.encodeToLSPAny()]
          )
        )
      )
    } catch {
      logger.info("Failed to get cursor info for reference count: \(error.forLogging, privacy: .public)")
    }
  }

  /// Resolves the display name of the build target containing the given document.
  private static func resolveTargetDisplayName(for snapshot: DocumentSnapshot, workspace: Workspace?) async -> String? {
    guard let workspace,
      let target = await workspace.buildServerManager.canonicalTarget(for: snapshot.uri),
      let buildTarget = await workspace.buildServerManager.buildTarget(named: target)
    else {
      return nil
    }
    return buildTarget.displayName
  }

  /// Returns playground code lenses if swift-play is available in the toolchain.
  private static func playgroundLenses(
    for snapshot: DocumentSnapshot,
    workspace: Workspace?,
    toolchain: Toolchain,
    syntaxTreeManager: SyntaxTreeManager,
    supportedCommands: [SupportedCodeLensCommand: String]
  ) async -> [CodeLens] {
    // "swift.play" CodeLens should be ignored if "swift-play" is not in the toolchain
    // as the client has no way of running it.
    guard toolchain.swiftPlay != nil,
      let workspace,
      let playCommand = supportedCommands[.play]
    else {
      return []
    }

    let playgrounds = await SwiftPlaygroundsScanner.findDocumentPlaygrounds(
      for: snapshot,
      workspace: workspace,
      syntaxTreeManager: syntaxTreeManager
    )
    return playgrounds.map {
      CodeLens(
        range: $0.range,
        command: Command(
          title: "Play \"\($0.label ?? $0.id)\"",
          command: playCommand,
          arguments: [$0.encodeToLSPAny()]
        )
      )
    }
  }
}
