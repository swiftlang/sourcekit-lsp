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

import Csourcekitd
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SourceKitLSP
import SwiftDiagnostics
import SwiftExtensions
import SwiftSyntax

import struct SourceKitLSP.Diagnostic

extension CodeAction {
  /// Creates a CodeAction from a list for sourcekit fixits.
  ///
  /// If this is from a note, the note's description should be passed as `fromNote`.
  init?(fixits: SKDResponseArray, in snapshot: DocumentSnapshot, fromNote: String?) {
    var edits: [TextEdit] = []
    // swift-format-ignore: ReplaceForEachWithForLoop
    // Reference is to `SKDResponseArray.forEach`, not `Array.forEach`.
    let editsMapped = fixits.forEach { (_, skfixit) -> Bool in
      if let edit = TextEdit(fixit: skfixit, in: snapshot) {
        edits.append(edit)
        return true
      }
      return false
    }

    if !editsMapped {
      logger.fault("Failed to construct TextEdits from response \(fixits)")
      return nil
    }

    if edits.isEmpty {
      return nil
    }

    let title: String
    if let fromNote = fromNote {
      title = fromNote
    } else {
      guard let generatedTitle = Self.title(for: edits, in: snapshot) else {
        return nil
      }
      title = generatedTitle
    }

    self.init(
      title: title,
      kind: .quickFix,
      diagnostics: nil,
      edit: WorkspaceEdit(changes: [snapshot.uri: edits])
    )
  }

  init?(_ fixIt: FixIt, in snapshot: DocumentSnapshot) {
    var textEdits = [TextEdit]()
    for edit in fixIt.edits {
      textEdits.append(TextEdit(range: snapshot.absolutePositionRange(of: edit.range), newText: edit.replacement))
    }

    self.init(
      title: fixIt.message.message.withFirstLetterUppercased(),
      kind: .quickFix,
      diagnostics: nil,
      edit: WorkspaceEdit(changes: [snapshot.uri: textEdits])
    )
  }

  private static func title(for edits: [TextEdit], in snapshot: DocumentSnapshot) -> String? {
    if edits.isEmpty {
      return nil
    }
    let startIndex = snapshot.index(of: edits[0].range.lowerBound)
    let endIndex = snapshot.index(of: edits[0].range.upperBound)
    guard startIndex <= endIndex,
      snapshot.text.indices.contains(startIndex),
      endIndex <= snapshot.text.endIndex
    else {
      return nil
    }
    let oldText = String(snapshot.text[startIndex..<endIndex])
    let description = Self.fixitTitle(replace: oldText, with: edits[0].newText)
    if edits.count == 1 {
      return description
    }
    return description + "..."
  }

  /// Describe a fixit's edit briefly.
  ///
  /// For example, "Replace 'x' with 'y'", or "Remove 'z'".
  package static func fixitTitle(replace oldText: String, with newText: String) -> String {
    switch (oldText.isEmpty, newText.isEmpty) {
    case (false, false):
      return "Replace '\(oldText)' with '\(newText)'"
    case (false, true):
      return "Remove '\(oldText)'"
    case (true, false):
      return "Insert '\(newText)'"
    case (true, true):
      logger.fault("Both oldText and newText of FixIt are empty")
      return "Fix"
    }
  }
}

extension TextEdit {

  /// Creates a TextEdit from a sourcekitd fixit response dictionary.
  init?(fixit: SKDResponseDictionary, in snapshot: DocumentSnapshot) {
    let keys = fixit.sourcekitd.keys
    if let utf8Offset: Int = fixit[keys.offset],
      let length: Int = fixit[keys.length],
      let replacement: String = fixit[keys.sourceText],
      length > 0 || !replacement.isEmpty
    {
      // Snippets are only suppored in code completion.
      // Remove SourceKit placeholders from Fix-Its because they can't be represented in the editor properly.
      let replacementWithoutPlaceholders = rewriteSourceKitPlaceholders(in: replacement, clientSupportsSnippets: false)

      // If both the replacement without placeholders and the fixit are empty, no TextEdit should be created.
      if replacementWithoutPlaceholders.isEmpty && length == 0 {
        return nil
      }

      let position = snapshot.positionOf(utf8Offset: utf8Offset)
      let endPosition = snapshot.positionOf(utf8Offset: utf8Offset + length)
      self.init(range: position..<endPosition, newText: replacementWithoutPlaceholders)
    } else {
      return nil
    }
  }
}

fileprivate extension String {
  /// Returns this string with the first letter uppercased.
  ///
  /// If the string does not start with a letter, no change is made to it.
  func withFirstLetterUppercased() -> String {
    if let firstLetter = self.first {
      return firstLetter.uppercased() + self.dropFirst()
    } else {
      return self
    }
  }
}

extension Diagnostic {
  /// Creates a diagnostic from a sourcekitd response dictionary.
  ///
  /// `snapshot` is the snapshot of the document for which the diagnostics are generated.
  /// `documentManager` is used to resolve positions of notes in secondary files.
  init?(
    _ diag: SKDResponseDictionary,
    in snapshot: DocumentSnapshot,
    documentManager: DocumentManager,
    useEducationalNoteAsCode: Bool
  ) {
    let keys = diag.sourcekitd.keys
    let values = diag.sourcekitd.values

    guard let filePath: String = diag[keys.filePath] else {
      logger.fault("Missing file path in diagnostic")
      return nil
    }

    func haveSameRealpath(_ lhs: DocumentURI, _ rhs: DocumentURI) -> Bool {
      guard let lhsFileURL = lhs.fileURL, let rhsFileURL = rhs.fileURL else {
        return false
      }
      do {
        return try lhsFileURL.realpath == rhsFileURL.realpath
      } catch {
        return false
      }
    }

    guard
      filePath == snapshot.uri.pseudoPath
        || haveSameRealpath(DocumentURI(filePath: filePath, isDirectory: false), snapshot.uri)
    else {
      logger.error("Ignoring diagnostic from a different file: \(filePath)")
      return nil
    }

    guard let message: String = diag[keys.description]?.withFirstLetterUppercased() else { return nil }

    var range: Range<Position>? = nil
    if let line: Int = diag[keys.line],
      let utf8Column: Int = diag[keys.column],
      line > 0, utf8Column > 0
    {
      range = Range(snapshot.positionOf(zeroBasedLine: line - 1, utf8Column: utf8Column - 1))
    } else if let utf8Offset: Int = diag[keys.offset] {
      range = Range(snapshot.positionOf(utf8Offset: utf8Offset))
    }

    // swift-format-ignore: ReplaceForEachWithForLoop
    // Reference is to `SKDResponseArray.forEach`, not `Array.forEach`.
    // If the diagnostic has a range associated with it that starts at the same location as the diagnostics position, use it to retrieve a proper range for the diagnostic, instead of just reporting a zero-length range.
    (diag[keys.ranges] as SKDResponseArray?)?.forEach { index, skRange in
      guard let utf8Offset: Int = skRange[keys.offset],
        let length: Int = skRange[keys.length]
      else {
        return true  // continue
      }
      let start = snapshot.positionOf(utf8Offset: utf8Offset)
      let end = snapshot.positionOf(utf8Offset: utf8Offset + length)
      guard start == range?.lowerBound else {
        return true
      }

      range = start..<end
      return false  // terminate forEach
    }

    guard let range = range else {
      return nil
    }

    var severity: LanguageServerProtocol.DiagnosticSeverity? = nil
    if let uid: sourcekitd_api_uid_t = diag[keys.severity] {
      switch uid {
      case values.diagError:
        severity = .error
      case values.diagWarning:
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
      let educationalNotePaths: SKDResponseArray = diag[keys.educationalNotePaths],
      educationalNotePaths.count > 0,
      let primaryPath = educationalNotePaths[0]
    {
      // Swift >= 6.2 returns a URL rather than a file path
      let url: URL? =
        if primaryPath.starts(with: "http") {
          URL(string: primaryPath)
        } else {
          URL(fileURLWithPath: primaryPath)
        }

      if let url {
        let name = url.deletingPathExtension().lastPathComponent
        code = .string(name)
        codeDescription = .init(href: DocumentURI(url))
      }
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
      // swift-format-ignore: ReplaceForEachWithForLoop
      // Reference is to `SKDResponseArray.forEach`, not `Array.forEach`.
      sknotes.forEach { (_, sknote) -> Bool in
        guard
          let note = DiagnosticRelatedInformation(
            sknote,
            primaryDocumentSnapshot: snapshot,
            documentManager: documentManager
          )
        else { return true }
        notes?.append(note)
        return true
      }
    }

    var tags: [DiagnosticTag] = []
    if let categories: SKDResponseArray = diag[keys.categories] {
      categories.forEachUID { (_, category) in
        switch category {
        case values.diagDeprecation:
          tags.append(.deprecated)
        case values.diagNoUsage:
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
      source: "SourceKit",
      message: message,
      tags: tags,
      relatedInformation: notes,
      codeActions: actions
    )
  }

  init(
    _ diag: SwiftDiagnostics.Diagnostic,
    in snapshot: DocumentSnapshot
  ) {
    // Start with a zero-length range based on the position.
    // If the diagnostic has highlights associated with it that start at the
    // position, use that as the diagnostic's range.
    var range = Range(snapshot.position(of: diag.position))
    for highlight in diag.highlights {
      let swiftSyntaxRange = highlight.positionAfterSkippingLeadingTrivia..<highlight.endPositionBeforeTrailingTrivia
      let highlightRange = snapshot.absolutePositionRange(of: swiftSyntaxRange)
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
      source: "SourceKit",
      message: diag.message,
      tags: nil,
      relatedInformation: relatedInformation,
      codeActions: codeActions
    )
  }
}

extension DiagnosticRelatedInformation {

  /// Creates related information from a sourcekitd note response dictionary.
  ///
  /// `primaryDocumentSnapshot` is the snapshot of the document for which the diagnostics are generated.
  /// `documentManager` is used to resolve positions of notes in secondary files.
  init?(_ diag: SKDResponseDictionary, primaryDocumentSnapshot: DocumentSnapshot, documentManager: DocumentManager) {
    let keys = diag.sourcekitd.keys

    guard let filePath: String = diag[keys.filePath] else {
      logger.fault("Missing file path in related diagnostic information")
      return nil
    }
    let uri = DocumentURI(filePath: filePath, isDirectory: false)
    let snapshot: DocumentSnapshot
    if filePath == primaryDocumentSnapshot.uri.pseudoPath {
      snapshot = primaryDocumentSnapshot
    } else if let loadedSnapshot = documentManager.latestSnapshotOrDisk(uri, language: .swift) {
      snapshot = loadedSnapshot
    } else {
      return nil
    }

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

    guard let message: String = diag[keys.description]?.withFirstLetterUppercased() else { return nil }

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

  init(_ note: Note, in snapshot: DocumentSnapshot) {
    let nodeRange = note.node.positionAfterSkippingLeadingTrivia..<note.node.endPositionBeforeTrailingTrivia
    self.init(
      location: Location(uri: snapshot.uri, range: snapshot.absolutePositionRange(of: nodeRange)),
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
  init?(_ uid: sourcekitd_api_uid_t, sourcekitd: SourceKitD) {
    switch uid {
    case sourcekitd.values.parseDiagStage:
      self = .parse
    case sourcekitd.values.semaDiagStage:
      self = .sema
    default:
      let uidDescription =
        if let cString = sourcekitd.api.uid_get_string_ptr(uid) {
          String(cString: cString)
        } else {
          "<nil>"
        }
      logger.fault("Unknown diagnostic stage \(uidDescription, privacy: .public)")
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
    #if RESILIENT_LIBRARIES
    @unknown default:
      fatalError("Unknown case")
    #endif
    }
  }
}
