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
import sourcekitd

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

    var notes: [DiagnosticRelatedInformation]? = nil
    if let sknotes: SKResponseArray = diag[keys.diagnostics] {
      notes = []
      sknotes.forEach { (_, sknote) -> Bool in
        guard let note = Diagnostic(sknote, in: snapshot) else { return true }
        notes?.append(DiagnosticRelatedInformation(
          location: Location(url: snapshot.document.url, range: note.range.asRange),
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
      relatedInformation: notes)
  }
}
