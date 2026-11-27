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

@preconcurrency import IndexStoreDB
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SKOptions
import SKUtilities
import SemanticIndex
import SourceKitD
import SourceKitLSP
import SwiftDiagnostics
import SwiftExtensions
import SwiftParserDiagnostics
import SwiftSyntax
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

import struct SourceKitLSP.Diagnostic

actor DiagnosticReportManager {
  /// A task to produce diagnostics, either from a diagnostics request to `sourcekitd` or by using the built-in swift-syntax.
  private typealias ReportTask = RefCountedCancellableTask<
    (report: RelatedFullDocumentDiagnosticReport, cachable: Bool)
  >

  private struct CacheKey: Hashable {
    let snapshotID: DocumentSnapshot.ID
    let buildSettings: SwiftCompileCommand?
  }

  private let sourcekitd: SourceKitD
  private let options: SourceKitLSPOptions
  private let syntaxTreeManager: SyntaxTreeManager
  private let documentManager: DocumentManager
  private let clientHasDiagnosticsCodeDescriptionSupport: Bool
  private let uncheckedIndexProvider: @Sendable () async -> UncheckedIndex?

  private nonisolated var keys: sourcekitd_api_keys { return sourcekitd.keys }
  private nonisolated var requests: sourcekitd_api_requests { return sourcekitd.requests }

  /// The cache that stores reportTasks for snapshot id and buildSettings
  ///
  /// - Note: The capacity has been chosen without scientific measurements.
  private var reportTaskCache = LRUCache<CacheKey, ReportTask>(capacity: 5)

  init(
    sourcekitd: SourceKitD,
    options: SourceKitLSPOptions,
    syntaxTreeManager: SyntaxTreeManager,
    documentManager: DocumentManager,
    clientHasDiagnosticsCodeDescriptionSupport: Bool,
    uncheckedIndexProvider: @escaping @Sendable () async -> UncheckedIndex?
  ) {
    self.sourcekitd = sourcekitd
    self.options = options
    self.syntaxTreeManager = syntaxTreeManager
    self.documentManager = documentManager
    self.clientHasDiagnosticsCodeDescriptionSupport = clientHasDiagnosticsCodeDescriptionSupport
    self.uncheckedIndexProvider = uncheckedIndexProvider
  }

  func diagnosticReport(
    for snapshot: DocumentSnapshot,
    buildSettings: SwiftCompileCommand?
  ) async throws -> RelatedFullDocumentDiagnosticReport {
    if let reportTask = reportTask(for: snapshot.id, buildSettings: buildSettings), await !reportTask.isCancelled {
      do {
        let cachedValue = try await reportTask.value
        if cachedValue.cachable {
          return cachedValue.report
        }
      } catch {
        // Do not cache failed requests
      }
    }
    let reportTask: ReportTask
    if let buildSettings, !buildSettings.isFallback {
      reportTask = ReportTask {
        return try await self.requestReport(with: snapshot, compilerArgs: buildSettings.compilerArgs)
      }
    } else {
      logger.log(
        "Producing syntactic diagnostics from the built-in swift-syntax because we \(buildSettings != nil ? "have fallback build settings" : "don't have build settings", privacy: .public))"
      )
      // If we don't have build settings or we only have fallback build settings,
      // sourcekitd won't be able to give us accurate semantic diagnostics.
      // Fall back to providing syntactic diagnostics from the built-in
      // swift-syntax. That's the best we can do for now.
      reportTask = ReportTask {
        return try await self.requestFallbackReport(with: snapshot)
      }
    }
    setReportTask(for: snapshot.id, buildSettings: buildSettings, reportTask: reportTask)
    return try await reportTask.value.report
  }

  func removeItemsFromCache(with uri: DocumentURI) async {
    reportTaskCache.removeAll(where: { $0.snapshotID.uri == uri })
  }

  private func requestReport(
    with snapshot: DocumentSnapshot,
    compilerArgs: [String]
  ) async throws -> (report: RelatedFullDocumentDiagnosticReport, cachable: Bool) {
    try Task.checkCancellation()

    let keys = self.keys

    let skreq = sourcekitd.dictionary([
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.compilerArgs: compilerArgs as [any SKDRequestValue],
    ])

    let dict: SKDResponseDictionary
    do {
      dict = try await self.sourcekitd.send(
        \.diagnostics,
        skreq,
        timeout: options.sourcekitdRequestTimeoutOrDefault,
        restartTimeout: options.semanticServiceRestartTimeoutOrDefault,
        documentUrl: snapshot.uri.arbitrarySchemeURL,
        fileContents: snapshot.text
      )
    } catch SKDError.requestFailed(let sourcekitdError) {
      var errorMessage = sourcekitdError
      if errorMessage.contains("semantic editor is disabled") {
        throw SKDError.requestFailed(sourcekitdError)
      }
      if errorMessage.hasPrefix("error response (Request Failed): error: ") {
        errorMessage = String(errorMessage.dropFirst(40))
      }
      let report = RelatedFullDocumentDiagnosticReport(items: [
        Diagnostic(
          range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0),
          severity: .error,
          source: "SourceKit",
          message: "Internal SourceKit error: \(errorMessage)"
        )
      ])
      // If generating the diagnostic report failed because of a sourcekitd problem, mark as as non-cachable because
      // executing the sourcekitd request again might succeed (eg. if sourcekitd has been restored after a crash).
      return (report, cachable: false)
    }

    try Task.checkCancellation()

    let rawDiagnostics: SKDResponseArray? = dict[keys.diagnostics]

    let hasMissingImportDiagnostic =
      rawDiagnostics?.compactMap { rawDiagnostic -> String? in
        guard let diagnosticID: String = rawDiagnostic[keys.id] else {
          return nil
        }

        return missingImportDiagnosticIDs.contains(diagnosticID) ? diagnosticID : nil
      }.isEmpty == false

    let checkedIndex: CheckedIndex?
    let syntaxTree: SourceFileSyntax?
    if hasMissingImportDiagnostic, let uncheckedIndex = await uncheckedIndex(timeout: .milliseconds(500)) {
      checkedIndex = uncheckedIndex.checked(for: .deletedFiles)
      syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    } else {
      checkedIndex = nil
      syntaxTree = nil
    }

    // A file often has multiple diagnostics about the same missing symbol. Only look each of them up once.
    var missingImportCodeActions: [MissingSymbol: CodeAction?] = [:]

    let diagnostics: [Diagnostic] =
      rawDiagnostics?.compactMap { rawDiagnostic in
        guard
          var diagnostic = Diagnostic(
            rawDiagnostic,
            in: snapshot,
            documentManager: documentManager,
            useEducationalNoteAsCode: self.clientHasDiagnosticsCodeDescriptionSupport
          )
        else {
          return nil
        }

        if let diagnosticID: String = rawDiagnostic[keys.id],
          missingImportDiagnosticIDs.contains(diagnosticID),
          let diagnosticDescription: String = rawDiagnostic[keys.description],
          let missingSymbol = missingSymbol(diagnosticID: diagnosticID, diagnosticDescription: diagnosticDescription),
          let checkedIndex,
          let syntaxTree
        {
          if missingImportCodeActions[missingSymbol] == nil {
            missingImportCodeActions[missingSymbol] = .some(
              try? missingImportCodeAction(
                for: missingSymbol,
                index: checkedIndex,
                syntaxTree: syntaxTree,
                snapshot: snapshot
              )
            )
          }
          if let codeAction = missingImportCodeActions[missingSymbol] ?? nil {
            diagnostic.codeActions = (diagnostic.codeActions ?? []) + [codeAction]
          }
        }

        return diagnostic
      } ?? []

    let report = RelatedFullDocumentDiagnosticReport(items: diagnostics)
    return (report, cachable: true)
  }

  private func requestFallbackReport(
    with snapshot: DocumentSnapshot
  ) async throws -> (report: RelatedFullDocumentDiagnosticReport, cachable: Bool) {
    // If we don't have build settings or we only have fallback build settings,
    // sourcekitd won't be able to give us accurate semantic diagnostics.
    // Fall back to providing syntactic diagnostics from the built-in
    // swift-syntax. That's the best we can do for now.
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let swiftSyntaxDiagnostics = ParseDiagnosticsGenerator.diagnostics(for: syntaxTree)
    let diagnostics = swiftSyntaxDiagnostics.compactMap { (diag) -> Diagnostic? in
      if diag.diagnosticID == StaticTokenError.editorPlaceholder.diagnosticID {
        // Ignore errors about editor placeholders in the source file, similar to how sourcekitd ignores them.
        return nil
      }
      return Diagnostic(diag, in: snapshot)
    }
    let report = RelatedFullDocumentDiagnosticReport(items: diagnostics)
    return (report, cachable: true)
  }

  /// The reportTask for the given document snapshot and buildSettings.
  private func reportTask(
    for snapshotID: DocumentSnapshot.ID,
    buildSettings: SwiftCompileCommand?
  ) -> ReportTask? {
    return reportTaskCache[CacheKey(snapshotID: snapshotID, buildSettings: buildSettings)]
  }

  /// Set the reportTask for the given document snapshot and buildSettings.
  private func setReportTask(
    for snapshotID: DocumentSnapshot.ID,
    buildSettings: SwiftCompileCommand?,
    reportTask: ReportTask
  ) {
    // Remove any reportTasks for old versions of this document.
    reportTaskCache.removeAll(where: { $0.snapshotID <= snapshotID })
    reportTaskCache[CacheKey(snapshotID: snapshotID, buildSettings: buildSettings)] = reportTask
  }

  private let missingImportDiagnosticIDs: Set<String> = [
    "cannot_find_type_in_scope",
    "cannot_find_type_in_scope_did_you_mean",
    "cannot_find_in_scope",
    "cannot_find_in_scope_corrected",
    "use_of_unresolved_identifier",
  ]

  /// These diagnostics also quote the name that the compiler suggests to use instead, eg.
  /// "cannot find 'Foo' in scope; did you mean 'Fooo'?". `cannot_find_in_scope_corrected` is emitted if typo correction
  /// finds a similar name in scope, `cannot_find_type_in_scope_did_you_mean` if the type has a different name in Swift,
  /// eg. `AnyClass` for `Class`.
  private let missingImportDiagnosticIDsWithSuggestedName: Set<String> = [
    "cannot_find_type_in_scope_did_you_mean",
    "cannot_find_in_scope_corrected",
  ]

  private func missingSymbol(diagnosticID: String, diagnosticDescription: String) -> MissingSymbol? {
    let components = diagnosticDescription.split(separator: "'", omittingEmptySubsequences: false)
    let expectedComponentCount = missingImportDiagnosticIDsWithSuggestedName.contains(diagnosticID) ? 5 : 3
    guard components.count == expectedComponentCount else {
      return nil
    }

    let symbolName = String(components[1])
    guard !symbolName.isEmpty else {
      return nil
    }
    return MissingSymbol(name: symbolName, isType: diagnosticID.hasPrefix("cannot_find_type_in_scope"))
  }

  private func missingImportCodeAction(
    for missingSymbol: MissingSymbol,
    index: CheckedIndex,
    syntaxTree: SourceFileSyntax,
    snapshot: DocumentSnapshot
  ) throws -> CodeAction? {
    guard let moduleName = try index.uniqueModuleProviding(missingSymbol) else {
      return nil
    }

    let existingImports = syntaxTree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }
    let edit: TextEdit
    if let nextImport = existingImports.first(where: { $0.path.trimmedDescription > moduleName }) {
      // Keep the imports sorted by inserting before the first import that is ordered after the new one.
      let insertionPosition = snapshot.position(of: nextImport.startOfLeadingComments)
      edit = TextEdit(
        range: insertionPosition..<insertionPosition,
        newText: "import \(moduleName)\n"
      )
    } else if let lastImport = existingImports.last {
      let insertionPosition = snapshot.position(of: lastImport.endPosition)
      edit = TextEdit(
        range: insertionPosition..<insertionPosition,
        newText: "\nimport \(moduleName)"
      )
    } else {
      let startOfFile = Position(line: 0, utf16index: 0)
      edit = TextEdit(
        range: startOfFile..<startOfFile,
        newText: "import \(moduleName)\n\n"
      )
    }

    return CodeAction(
      title: "Add import for '\(moduleName)'",
      kind: .quickFix,
      diagnostics: nil,
      edit: WorkspaceEdit(changes: [snapshot.uri: [edit]])
    )
  }

  private func uncheckedIndex(timeout: Duration) async -> UncheckedIndex? {
    let uncheckedIndexProvider = self.uncheckedIndexProvider

    do {
      return try await withTimeout(timeout) {
        await uncheckedIndexProvider()
      }
    } catch {
      return nil
    }
  }
}

/// A symbol that the compiler could not find in scope.
private struct MissingSymbol: Hashable {
  let name: String

  /// Whether the symbol is used as a type, in which case it can't be a function.
  let isType: Bool
}

fileprivate extension CheckedIndex {
  func uniqueModuleProviding(_ missingSymbol: MissingSymbol) throws -> String? {
    var moduleName: String?

    /// Sets `moduleName` to the module that defines the symbol of `occurrence`. Returns `false` and resets `moduleName`
    /// if the symbol is defined in multiple modules.
    func recordModule(of occurrence: SymbolOccurrence) -> Bool {
      guard occurrence.roles.contains(.definition) || occurrence.roles.contains(.declaration) else {
        return true
      }

      // An unqualified lookup can't find members, even if their module is imported. The exception are operators,
      // which are found even if they are declared inside a type.
      guard
        occurrence.symbol.isOperator || !occurrence.relations.contains(where: { $0.roles.contains(.childOf) })
      else {
        return true
      }

      let occurrenceModuleName = occurrence.location.moduleName
      guard !occurrenceModuleName.isEmpty else {
        return true
      }

      guard moduleName == nil || moduleName == occurrenceModuleName else {
        moduleName = nil
        return false
      }

      moduleName = occurrenceModuleName
      return true
    }

    guard try forEachCanonicalSymbolOccurrence(byName: missingSymbol.name, body: recordModule) else {
      return nil
    }
    if moduleName != nil || missingSymbol.isType {
      return moduleName
    }

    // Functions are indexed with their argument labels, eg. `foo(_:)`, but the diagnostic only names `foo`. The index
    // can only look up symbols by their full name, so finding the function requires a scan of all symbol names.
    guard
      try forEachCanonicalSymbolOccurrence(
        containing: "\(missingSymbol.name)(",
        anchorStart: true,
        anchorEnd: false,
        subsequence: false,
        ignoreCase: false,
        body: recordModule
      )
    else {
      return nil
    }
    return moduleName
  }
}

fileprivate extension Symbol {
  var isOperator: Bool {
    switch subKind {
    case .swiftPrefixOperator, .swiftPostfixOperator, .swiftInfixOperator: return true
    default: return false
    }
  }
}

fileprivate extension ImportDeclSyntax {
  /// The start of the comments that are attached to this import, ie. that are not separated from it by an empty line.
  /// If no comments are attached to the import, the start of the line that contains the import.
  var startOfLeadingComments: AbsolutePosition {
    var position = self.position
    var startOfLeadingComments = position
    var lineContainsComment = false
    for piece in leadingTrivia {
      position += piece.sourceLength
      switch piece {
      case .newlines(let count), .carriageReturns(let count), .carriageReturnLineFeeds(let count):
        if count > 1 || !lineContainsComment {
          startOfLeadingComments = position
        }
        lineContainsComment = false
      default:
        lineContainsComment = lineContainsComment || piece.isComment
      }
    }
    return startOfLeadingComments
  }
}
