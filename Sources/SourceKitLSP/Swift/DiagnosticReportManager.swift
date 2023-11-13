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

import LSPLogging
import LanguageServerProtocol
import SourceKitD
import SwiftParserDiagnostics

actor DiagnosticReportManager {
  /// A task to produce diagnostics, either from a diagnostics request to `sourcektid` or by using the built-in swift-syntax.
  private typealias ReportTask = Task<RelatedFullDocumentDiagnosticReport, Error>

  private let sourcekitd: SourceKitD
  private let syntaxTreeManager: SyntaxTreeManager
  private let documentManager: DocumentManager
  private let clientHasDiagnosticsCodeDescriptionSupport: Bool

  private nonisolated var keys: sourcekitd_keys { return sourcekitd.keys }
  private nonisolated var requests: sourcekitd_requests { return sourcekitd.requests }

  /// The cache that stores reportTasks for snapshot id and buildSettings
  ///
  /// Conceptually, this is a dictionary. To prevent excessive memory usage we
  /// only keep `cacheSize` entries within the array. Older entries are at the
  /// end of the list, newer entries at the front.
  private var reportTaskCache:
    [(
      snapshotID: DocumentSnapshot.ID,
      buildSettings: SwiftCompileCommand?,
      reportTask: ReportTask
    )] = []

  /// The number of reportTasks to keep
  ///
  /// - Note: This has been chosen without scientific measurements.
  private let cacheSize = 5

  init(
    sourcekitd: SourceKitD,
    syntaxTreeManager: SyntaxTreeManager,
    documentManager: DocumentManager,
    clientHasDiagnosticsCodeDescriptionSupport: Bool
  ) {
    self.sourcekitd = sourcekitd
    self.syntaxTreeManager = syntaxTreeManager
    self.documentManager = documentManager
    self.clientHasDiagnosticsCodeDescriptionSupport = clientHasDiagnosticsCodeDescriptionSupport
  }

  func diagnosticReport(
    for snapshot: DocumentSnapshot,
    buildSettings: SwiftCompileCommand?
  ) async throws -> RelatedFullDocumentDiagnosticReport {
    if let reportTask = reportTask(for: snapshot.id, buildSettings: buildSettings) {
      return try await reportTask.value
    }
    let reportTask: Task<RelatedFullDocumentDiagnosticReport, Error>
    if let buildSettings, !buildSettings.isFallback {
      reportTask = Task {
        return try await requestReport(with: snapshot, compilerArgs: buildSettings.compilerArgs)
      }
    } else {
      logger.log(
        "Producing syntactic diagnostics from the built-in swift-syntax because we \(buildSettings != nil ? "have fallback build settings" : "don't have build settings", privacy: .public))"
      )
      // If we don't have build settings or we only have fallback build settings,
      // sourcekitd won't be able to give us accurate semantic diagnostics.
      // Fall back to providing syntactic diagnostics from the built-in
      // swift-syntax. That's the best we can do for now.
      reportTask = Task {
        return try await requestFallbackReport(with: snapshot)
      }
    }
    setReportTask(for: snapshot.id, buildSettings: buildSettings, reportTask: reportTask)
    return try await reportTask.value
  }

  func removeItemsFromCache(with uri: DocumentURI) async {
    for item in reportTaskCache {
      if item.snapshotID.uri == uri {
        item.reportTask.cancel()
      }
    }
    reportTaskCache.removeAll(where: { $0.snapshotID.uri == uri })
  }

  private func requestReport(
    with snapshot: DocumentSnapshot,
    compilerArgs: [String]
  ) async throws -> LanguageServerProtocol.RelatedFullDocumentDiagnosticReport {
    try Task.checkCancellation()

    let keys = self.keys

    let skreq = sourcekitd.dictionary([
      keys.request: requests.diagnostics,
      keys.sourcefile: snapshot.uri.pseudoPath,
      keys.compilerargs: compilerArgs as [SKDValue],
    ])

    let dict = try await self.sourcekitd.send(skreq, fileContents: snapshot.text)

    try Task.checkCancellation()
    guard (try? documentManager.latestSnapshot(snapshot.uri).id) == snapshot.id else {
      // Check that the document wasn't modified while we were getting diagnostics. This could happen because we are
      // calling `fullDocumentDiagnosticReport` from `publishDiagnosticsIfNeeded` outside of `messageHandlingQueue`
      // and thus a concurrent edit is possible while we are waiting for the sourcekitd request to return a result.
      throw ResponseError.unknown("Document was modified while loading diagnostics")
    }

    let diagnostics: [Diagnostic] =
      dict[keys.diagnostics]?.compactMap({ diag in
        Diagnostic(
          diag,
          in: snapshot,
          useEducationalNoteAsCode: self.clientHasDiagnosticsCodeDescriptionSupport
        )
      }) ?? []

    return RelatedFullDocumentDiagnosticReport(items: diagnostics)
  }

  private func requestFallbackReport(
    with snapshot: DocumentSnapshot
  ) async throws -> LanguageServerProtocol.RelatedFullDocumentDiagnosticReport {
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
    return RelatedFullDocumentDiagnosticReport(items: diagnostics)
  }

  /// The reportTask for the given document snapshot and buildSettings.
  private func reportTask(
    for snapshotID: DocumentSnapshot.ID,
    buildSettings: SwiftCompileCommand?
  ) -> ReportTask? {
    return reportTaskCache.first(where: { $0.snapshotID == snapshotID && $0.buildSettings == buildSettings })?
      .reportTask
  }

  /// Set the reportTask for the given document snapshot and buildSettings.
  ///
  /// If we are already storing `cacheSize` many reports, the oldest one
  /// will get discarded.
  private func setReportTask(
    for snapshotID: DocumentSnapshot.ID,
    buildSettings: SwiftCompileCommand?,
    reportTask: ReportTask
  ) {
    reportTaskCache.insert((snapshotID, buildSettings, reportTask), at: 0)

    // Remove any reportTasks for old versions of this document.
    reportTaskCache.removeAll(where: { $0.snapshotID < snapshotID })

    // If we still have more than `cacheSize` reportTasks, delete the ones that
    // were produced last. We can always re-request them on-demand.
    while reportTaskCache.count > cacheSize {
      reportTaskCache.removeLast()
    }
  }
}
