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

import LSPLogging
import LanguageServerProtocol
import SKSupport
import SourceKitD
import SwiftDiagnostics

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
      logger.fault("failed to construct TextEdits from response \(fixits)")
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
        logger.fault("position mapped, but indices failed for edit range \(String(reflecting: edits[0]))")
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
      edit: WorkspaceEdit(changes: [snapshot.uri: edits])
    )
  }

  init?(_ fixIt: FixIt, in snapshot: DocumentSnapshot) {
    // FIXME: Once https://github.com/apple/swift-syntax/pull/2226 is merged and
    // FixItApplier is public, use it to compute the edits that should be
    // applied to the source.
    return nil
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
      // Snippets are only suppored in code completion.
      // Remove SourceKit placeholders from Fix-Its because they can't be represented in the editor properly.
      let replacementWithoutPlaceholders = rewriteSourceKitPlaceholders(
        inString: replacement,
        clientSupportsSnippets: false
      )

      // If both the replacement without placeholders and the fixit are empty, no TextEdit should be created.
      if (replacementWithoutPlaceholders.isEmpty && length == 0) {
        return nil
      }

      self.init(range: position..<endPosition, newText: replacementWithoutPlaceholders)
    } else {
      return nil
    }
  }
}

extension Diagnostic {

  /// Creates a diagnostic from a sourcekitd response dictionary.
  init?(
    _ diag: SKDResponseDictionary,
    in snapshot: DocumentSnapshot,
    useEducationalNoteAsCode: Bool
  ) {
    // FIXME: this assumes that the diagnostics are all in the same file.

    let keys = diag.sourcekitd.keys
    let values = diag.sourcekitd.values

    guard let message: String = diag[keys.description] else { return nil }

    var range: Range<Position>? = nil
    if let line: Int = diag[keys.line],
      let utf8Column: Int = diag[keys.column],
      line > 0, utf8Column > 0
    {
      range = snapshot.positionOf(zeroBasedLine: line - 1, utf8Column: utf8Column - 1).map(Range.init)
    } else if let utf8Offset: Int = diag[keys.offset] {
      range = snapshot.positionOf(utf8Offset: utf8Offset).map(Range.init)
    }

    // If the diagnostic has a range associated with it that starts at the same location as the diagnostics position, use it to retrieve a proper range for the diagnostic, instead of just reporting a zero-length range.
    (diag[keys.ranges] as SKDResponseArray?)?.forEach { index, skRange in
      if let utf8Offset: Int = skRange[keys.offset],
        let start = snapshot.positionOf(utf8Offset: utf8Offset),
        start == range?.lowerBound,
        let length: Int = skRange[keys.length],
        let end = snapshot.positionOf(utf8Offset: utf8Offset + length)
      {
        range = start..<end
        return false
      } else {
        return true
      }
    }

    guard let range = range else {
      return nil
    }

    var severity: LanguageServerProtocol.DiagnosticSeverity? = nil
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
      let action = CodeAction(fixits: skfixits, in: snapshot, fromNote: nil)
    {
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

    var tags: [DiagnosticTag] = []
    if let categories: SKDResponseArray = diag[keys.categories] {
      categories.forEachUID { (_, category) in
        switch category {
        case values.diag_category_deprecation:
          tags.append(.deprecated)
        case values.diag_category_no_usage:
          tags.append(.unnecessary)
        default:
          break
        }
        return true
      }
    }

    self.init(
      range: range,
      severity: severity,
      code: code,
      codeDescription: codeDescription,
      source: "sourcekitd",
      message: message,
      tags: tags,
      relatedInformation: notes,
      codeActions: actions
    )
  }

  init?(
    _ diag: SwiftDiagnostics.Diagnostic,
    in snapshot: DocumentSnapshot
  ) {
    guard let position = snapshot.position(of: diag.position) else {
      logger.error(
        """
        Cannot construct Diagnostic from SwiftSyntax diagnostic because its UTF-8 offset \(diag.position.utf8Offset) \
        is out of range of the source file \(snapshot.uri.forLogging)
        """
      )
      return nil
    }
    // Start with a zero-length range based on the position.
    // If the diagnostic has highlights associated with it that start at the
    // position, use that as the diagnostic's range.
    var range = Range(position)
    for highlight in diag.highlights {
      let swiftSyntaxRange = highlight.positionAfterSkippingLeadingTrivia..<highlight.endPositionBeforeTrailingTrivia
      guard let highlightRange = snapshot.range(of: swiftSyntaxRange) else {
        break
      }
      if range.upperBound == highlightRange.lowerBound {
        range = range.lowerBound..<highlightRange.upperBound
      } else {
        break
      }
    }

    let relatedInformation = diag.notes.compactMap { DiagnosticRelatedInformation($0, in: snapshot) }
    let codeActions = diag.fixIts.compactMap { CodeAction($0, in: snapshot) }

    self.init(
      range: range,
      severity: diag.diagMessage.severity.lspSeverity,
      code: nil,
      codeDescription: nil,
      source: "SwiftSyntax",
      message: diag.message,
      tags: nil,
      relatedInformation: relatedInformation,
      codeActions: codeActions
    )
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
      let action = CodeAction(fixits: skfixits, in: snapshot, fromNote: message)
    {
      actions = [action]
    }

    self.init(
      location: Location(uri: snapshot.uri, range: Range(position!)),
      message: message,
      codeActions: actions
    )
  }

  init?(_ note: Note, in snapshot: DocumentSnapshot) {
    let nodeRange = note.node.positionAfterSkippingLeadingTrivia..<note.node.endPositionBeforeTrailingTrivia
    guard let range = snapshot.range(of: nodeRange) else {
      logger.error(
        """
        Cannot construct DiagnosticRelatedInformation because the range \(nodeRange, privacy: .public) \
        is out of range of the source file \(snapshot.uri.forLogging).
        """
      )
      return nil
    }
    self.init(
      location: Location(uri: snapshot.uri, range: range),
      message: note.message
    )
  }
}

extension Diagnostic {
  func withRange(_ newRange: Range<Position>) -> Diagnostic {
    var updated = self
    updated.range = newRange
    return updated
  }
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
      logger.fault("unknown diagnostic stage \(desc ?? "nil", privacy: .public)")
      return nil
    }
  }
}

fileprivate extension SwiftDiagnostics.DiagnosticSeverity {
  var lspSeverity: LanguageServerProtocol.DiagnosticSeverity {
    switch self {
    case .error: return .error
    case .warning: return .warning
    case .note: return .information
    case .remark: return .hint
    }
  }
}
