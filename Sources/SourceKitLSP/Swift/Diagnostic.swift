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
import SourceKitD

extension CodeAction {

  /// Creates a CodeAction from a list for sourcekit fixits.
  ///
  /// If this is from a note, the note's description should be passed as `fromNote`.
  init?(fixits: SKDResponseArray, in snapshot: DocumentSnapshot, fromNote: String?) {
    var edits: [TextEdit] = []
    let editsMapped = fixits.forEach { (_, skfixit) -> Bool in
      if let edit = TextEdit(fixit: skfixit, in: snapshot) {
        edits.append(edit)
        return true
      }
      return false
    }

    if !editsMapped {
      log("failed to construct TextEdits from response \(fixits)", level: .warning)
      return nil
    }

    if edits.isEmpty {
      return nil
    }

    let title: String
    if let fromNote = fromNote {
      title = fromNote
    } else {
      guard let startIndex = snapshot.index(of: edits[0].range.lowerBound),
            let endIndex = snapshot.index(of: edits[0].range.upperBound),
            startIndex <= endIndex,
            snapshot.text.indices.contains(startIndex),
            endIndex <= snapshot.text.endIndex
      else {
        logAssertionFailure("position mapped, but indices failed for edit range \(edits[0])")
        return nil
      }
      let oldText = String(snapshot.text[startIndex..<endIndex])
      let description = Self.fixitTitle(replace: oldText, with: edits[0].newText)
      if edits.count == 1 {
        title = description
      } else {
        title = description + "..."
      }
    }

    self.init(
      title: title,
      kind: .quickFix,
      diagnostics: nil,
      edit: WorkspaceEdit(changes: [snapshot.document.uri:edits]))
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

extension TextEdit {

  /// Creates a TextEdit from a sourcekitd fixit response dictionary.
  init?(fixit: SKDResponseDictionary, in snapshot: DocumentSnapshot) {
    let keys = fixit.sourcekitd.keys
    if let utf8Offset: Int = fixit[keys.offset],
       let length: Int = fixit[keys.length],
       let replacement: String = fixit[keys.sourcetext],
       let position = snapshot.positionOf(utf8Offset: utf8Offset),
       let endPosition = snapshot.positionOf(utf8Offset: utf8Offset + length),
       length > 0 || !replacement.isEmpty
    {
      self.init(range: position..<endPosition, newText: replacement)
    } else {
      return nil
    }
  }
}

extension Diagnostic {

  /// Creates a diagnostic from a sourcekitd response dictionary.
  init?(_ diag: SKDResponseDictionary,
        in snapshot: DocumentSnapshot,
        useEducationalNoteAsCode: Bool) {
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

    var code: DiagnosticCode? = nil
    var codeDescription: CodeDescription? = nil
    // If this diagnostic has one or more educational notes, the first one is
    // treated as primary and used to fill in the diagnostic code and
    // description. `useEducationalNoteAsCode` ensures a note name is only used
    // as a code if the cline supports an extended code description.
    if useEducationalNoteAsCode,
       let educationalNotePaths: SKDResponseArray = diag[keys.educational_note_paths],
       educationalNotePaths.count > 0,
       let primaryPath = educationalNotePaths[0]
    {
      let url = URL(fileURLWithPath: primaryPath)
      let name = url.deletingPathExtension().lastPathComponent
      code = .string(name)
      codeDescription = .init(href: DocumentURI(url))
    }

    var actions: [CodeAction]? = nil
    if let skfixits: SKDResponseArray = diag[keys.fixits],
       let action = CodeAction(fixits: skfixits, in: snapshot, fromNote: nil) {
      actions = [action]
    }

    var notes: [DiagnosticRelatedInformation]? = nil
    if let sknotes: SKDResponseArray = diag[keys.diagnostics] {
      notes = []
      sknotes.forEach { (_, sknote) -> Bool in
        guard let note = DiagnosticRelatedInformation(sknote, in: snapshot) else { return true }
        notes?.append(note)
        return true
      }
    }

    self.init(
      range: Range(position!),
      severity: severity,
      code: code,
      codeDescription: codeDescription,
      source: "sourcekitd",
      message: message,
      relatedInformation: notes,
      codeActions: actions)
  }
}

extension DiagnosticRelatedInformation {

  /// Creates related information from a sourcekitd note response dictionary.
  init?(_ diag: SKDResponseDictionary, in snapshot: DocumentSnapshot) {
    let keys = diag.sourcekitd.keys

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

    guard let message: String = diag[keys.description] else { return nil }

    var actions: [CodeAction]? = nil
    if let skfixits: SKDResponseArray = diag[keys.fixits],
       let action = CodeAction(fixits: skfixits, in: snapshot, fromNote: message) {
      actions = [action]
    }

    self.init(
      location: Location(uri: snapshot.document.uri, range: Range(position!)),
      message: message,
      codeActions: actions)
  }
}

struct CachedDiagnostic {
  var diagnostic: Diagnostic
  var stage: DiagnosticStage
}

extension CachedDiagnostic {
  init?(_ diag: SKDResponseDictionary,
        in snapshot: DocumentSnapshot,
        useEducationalNoteAsCode: Bool) {
    let sk = diag.sourcekitd
    guard let diagnostic = Diagnostic(diag,
                                      in: snapshot,
                                      useEducationalNoteAsCode: useEducationalNoteAsCode) else {
      return nil
    }
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
///
/// However, if fallback arguments are being used, we withhold semantic diagnostics in favor of only
/// emitting syntactic diagnostics.
func mergeDiagnostics(
  old: [CachedDiagnostic],
  new: [CachedDiagnostic],
  stage: DiagnosticStage,
  isFallback: Bool
) -> [CachedDiagnostic] {
  if stage == .sema {
    return isFallback ? old.filter { $0.stage == .parse } : new
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
  init?(_ uid: sourcekitd_uid_t, sourcekitd: SourceKitD) {
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
