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

import LanguageServerProtocol
import LSPLogging
import SKSupport
import sourcekitd

extension CodeAction {
  init?(fixit: SKResponseDictionary, in snapshot: DocumentSnapshot) {
    let keys = fixit.sourcekitd.keys

    guard let utf8Offset: Int = fixit[keys.offset],
          let length: Int = fixit[keys.length],
          let replacement: String = fixit[keys.sourcetext],
          let position = snapshot.positionOf(utf8Offset: utf8Offset),
          let endPosition = snapshot.positionOf(utf8Offset: utf8Offset + length),
          let startIndex = snapshot.indexOf(utf8Offset: utf8Offset),
          let endIndex = snapshot.indexOf(utf8Offset: utf8Offset + length),
          length > 0 || !replacement.isEmpty
    else {
      return nil
    }

    let range = position..<endPosition
    let original = String(snapshot.text[startIndex..<endIndex])
    let title = Self.fixitTitle(replace: original, with: replacement)
    let workspaceEdit = WorkspaceEdit(
      changes: [snapshot.document.uri:[TextEdit(range: range, newText: replacement)]])

    self.init(
      title: title,
      kind: .quickFix,
      diagnostics: nil,
      edit: workspaceEdit)
  }

  /// Describe a fixit's edit briefly.
  ///
  /// For example, "Replace 'x' with 'y'", or "Remove 'z'".
  public static func fixitTitle(replace oldText: String, with newText: String) -> String {
    switch (oldText.isEmpty, newText.isEmpty) {
    case (false, false):
      return "Replace '\(oldText)' with '\(newText)'"
    case (false, true):
      return "Remove '\(oldText)'"
    case (true, false):
      return "Insert '\(newText)'"
    case (true, true):
      preconditionFailure("FixIt makes no changes")
    }
  }
}

extension Diagnostic {

  /// Creates a diagnostic from a sourcekitd response dictionary.
  init?(_ diag: SKResponseDictionary, in snapshot: DocumentSnapshot) {
    // FIXME: this assumes that the diagnostics are all in the same file.

    let keys = diag.sourcekitd.keys
    let values = diag.sourcekitd.values

    guard let message: String = diag[keys.description] else { return nil }

    var position: Position? = nil
    if let line: Int = diag[keys.line],
       let utf8Column: Int = diag[keys.column],
       line > 0, utf8Column > 0
    {
      position = snapshot.positionOf(zeroBasedLine: line - 1, utf8Column: utf8Column - 1)
    } else if let utf8Offset: Int = diag[keys.offset] {
      position = snapshot.positionOf(utf8Offset: utf8Offset)
    }

    if position == nil {
      return nil
    }

    var severity: DiagnosticSeverity? = nil
    if let uid: sourcekitd_uid_t = diag[keys.severity] {
      switch uid {
      case values.diag_error:
        severity = .error
      case values.diag_warning:
        severity = .warning
      default:
        break
      }
    }

    var fixits: [CodeAction]? = nil
    if let skfixits: SKResponseArray = diag[keys.fixits] {
      fixits = []
      skfixits.forEach { (_, skfixit) -> Bool in
        if let codeAction = CodeAction(fixit: skfixit, in: snapshot) {
          fixits?.append(codeAction)
        }
        return true
      }
    }

    var notes: [DiagnosticRelatedInformation]? = nil
    if let sknotes: SKResponseArray = diag[keys.diagnostics] {
      notes = []
      sknotes.forEach { (_, sknote) -> Bool in
        guard let note = Diagnostic(sknote, in: snapshot) else { return true }
        notes?.append(DiagnosticRelatedInformation(
          location: Location(uri: snapshot.document.uri, range: note.range),
          message: note.message
        ))
        return true
      }
    }

    self.init(
      range: Range(position!),
      severity: severity,
      code: nil,
      source: "sourcekitd",
      message: message,
      relatedInformation: notes,
      codeActions: fixits)
  }
}

struct CachedDiagnostic {
  var diagnostic: Diagnostic
  var stage: DiagnosticStage
}

extension CachedDiagnostic {
  init?(_ diag: SKResponseDictionary, in snapshot: DocumentSnapshot) {
    let sk = diag.sourcekitd
    guard let diagnostic = Diagnostic(diag, in: snapshot) else { return nil }
    self.diagnostic = diagnostic
    let stageUID: sourcekitd_uid_t? = diag[sk.keys.diagnostic_stage]
    self.stage = stageUID.flatMap { DiagnosticStage($0, sourcekitd: sk) } ?? .parse
  }
}

/// Returns the new diagnostics after merging in any existing diagnostics from a higher diagnostic
/// stage that should not be cleared yet.
///
/// Sourcekitd returns parse diagnostics immediately after edits, but we do not want to clear the
/// semantic diagnostics until we have semantic level diagnostics from after the edit.
func mergeDiagnostics(old: [CachedDiagnostic], new: [CachedDiagnostic], stage: DiagnosticStage) -> [CachedDiagnostic] {
  if stage == .sema {
    return new
  }

#if DEBUG
  if let sema = new.first(where: { $0.stage == .sema }) {
    log("unexpected semantic diagnostic in parse diagnostics \(sema.diagnostic)", level: .warning)
  }
#endif
  return new.filter { $0.stage == .parse } + old.filter { $0.stage == .sema }
}

/// Whether a diagostic is semantic or syntatic (parse).
enum DiagnosticStage: Hashable {
  case parse
  case sema
}

extension DiagnosticStage {
  init?(_ uid: sourcekitd_uid_t, sourcekitd: SwiftSourceKitFramework) {
    switch uid {
      case sourcekitd.values.diag_stage_parse:
        self = .parse
      case sourcekitd.values.diag_stage_sema:
        self = .sema
      default:
        let desc = sourcekitd.api.uid_get_string_ptr(uid).map { String(cString: $0) }
        log("unknown diagnostic stage \(desc ?? "nil")", level: .warning)
        return nil
    }
  }
}
