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
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SKOptions
import SKUtilities
import SourceKitD
import SourceKitLSP
import SwiftDiagnostics
import SwiftExtensions
import SwiftParserDiagnostics
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
    clientHasDiagnosticsCodeDescriptionSupport: Bool
  ) {
    self.sourcekitd = sourcekitd
    self.options = options
    self.syntaxTreeManager = syntaxTreeManager
    self.documentManager = documentManager
    self.clientHasDiagnosticsCodeDescriptionSupport = clientHasDiagnosticsCodeDescriptionSupport
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
    // If we don't have build settings or we only have fallback build settings, sourcekitd won't be able to give us
    // accurate semantic diagnostics.
    // Fall back to providing syntactic diagnostics from the built-in swift-syntax. That's the best we can do for now.
    // The only exception is if the file starts with a shebang. In that case we know that the file can be executed on
    // its own without additional compiler arguments.
    if let buildSettings, !buildSettings.isFallback || snapshot.text.starts(with: "#!") {
      reportTask = ReportTask {
        return try await self.requestReport(with: snapshot, compilerArgs: buildSettings.compilerArgs)
      }
    } else {
      logger.log(
        "Producing syntactic diagnostics from the built-in swift-syntax because we \(buildSettings != nil ? "have fallback build settings" : "don't have build settings", privacy: .public))"
      )
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

    let diagnostics: [Diagnostic] =
      dict[keys.diagnostics]?.compactMap({ diag in
        Diagnostic(
          diag,
          in: snapshot,
          documentManager: documentManager,
          useEducationalNoteAsCode: self.clientHasDiagnosticsCodeDescriptionSupport
        )
      }) ?? []

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
}
