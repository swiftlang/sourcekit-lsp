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
import TSCBasic
import SourceKitD

/// Detailed information about the result of a specific refactoring operation.
///
/// Wraps the information returned by sourcekitd's `semantic_refactoring` request, such as the necessary edits and placeholder locations.
struct SemanticRefactoring {

  /// The title of the refactoring action.
  var title: String

  /// The resulting `WorkspaceEdit` of a `semantic_refactoring` request.
  var edit: WorkspaceEdit

  init(_ title: String, _ edit: WorkspaceEdit) {
    self.title = title
    self.edit = edit
  }

  /// Create a `SemanticRefactoring` from a sourcekitd response dictionary, if possible.
  ///
  /// - Parameters:
  ///   - title: The title of the refactoring action.
  ///   - dict: Response dictionary to extract information from.
  ///   - url: The client URL that triggered the `semantic_refactoring` request.
  ///   - keys: The sourcekitd key set to use for looking up into `dict`.
  init?(_ title: String, _ dict: SKDResponseDictionary, _ snapshot: DocumentSnapshot, _ keys: sourcekitd_keys) {
    guard let categorizedEdits: SKDResponseArray = dict[keys.categorizededits] else {
      return nil
    }

    var textEdits = [TextEdit]()

    categorizedEdits.forEach { _, value in
      guard let edits: SKDResponseArray = value[keys.edits] else {
        return false
      }
      edits.forEach { _, value in
        // The LSP is zero based, but semantic_refactoring is one based.
        if let startLine: Int = value[keys.line],
           let startColumn: Int = value[keys.column],
           let startPosition = snapshot.positionOf(zeroBasedLine: startLine - 1,
                                                   utf8Column: startColumn - 1),
           let endLine: Int = value[keys.endline],
           let endColumn: Int = value[keys.endcolumn],
           let endPosition = snapshot.positionOf(zeroBasedLine: endLine - 1,
                                                 utf8Column: endColumn - 1),
           let text: String = value[keys.text]
        {
          let edit = TextEdit(range: startPosition..<endPosition, newText: text)
          textEdits.append(edit)
        }
        return true
      }
      return true
    }

    guard textEdits.isEmpty == false else {
      return nil
    }

    self.title = title
    self.edit = WorkspaceEdit(changes: [snapshot.document.uri: textEdits])
  }
}

/// An error from a cursor info request.
enum SemanticRefactoringError: Error {

  /// The given URL is not a known document.
  case unknownDocument(DocumentURI)

  /// The given position range is invalid.
  case invalidRange(Range<Position>)

  /// The given position failed to convert to UTF-8.
  case failedToRetrieveOffset(Range<Position>)

  /// The underlying sourcekitd request failed with the given error.
  case responseError(ResponseError)

  /// The underlying sourcekitd reported no edits for this action.
  case noEditsNeeded(DocumentURI)
}

extension SemanticRefactoringError: CustomStringConvertible {
  var description: String {
    switch self {
    case .unknownDocument(let url):
      return "failed to find snapshot for url \(url)"
    case .invalidRange(let range):
      return "failed to refactor due to invalid range: \(range)"
    case .failedToRetrieveOffset(let range):
      return "Failed to convert range to UTF-8 offset: \(range)"
    case .responseError(let error):
      return "\(error)"
    case .noEditsNeeded(let url):
      return "no edits reported for semantic refactoring action for url \(url)"
    }
  }
}

extension SwiftLanguageServer {

  /// Provides detailed information about the result of a specific refactoring operation.
  ///
  /// Wraps the information returned by sourcekitd's `semantic_refactoring` request, such as the necessary edits and placeholder locations.
  ///
  /// - Parameters:
  ///   - url: Document URL in which to perform the request. Must be an open document.
  ///   - command: The semantic refactor `Command` that triggered this request.
  ///   - completion: Completion block to asynchronously receive the SemanticRefactoring data, or error.
  func semanticRefactoring(
    _ refactorCommand: SemanticRefactorCommand,
    _ completion: @escaping (Result<SemanticRefactoring, SemanticRefactoringError>) -> Void)
  {
    let keys = self.keys

    queue.async {
      let uri = refactorCommand.textDocument.uri
      guard let snapshot = self.documentManager.latestSnapshot(uri) else {
        return completion(.failure(.unknownDocument(uri)))
      }
      guard let offsetRange = snapshot.utf8OffsetRange(of: refactorCommand.positionRange) else {
        return completion(.failure(.failedToRetrieveOffset(refactorCommand.positionRange)))
      }
      let line = refactorCommand.positionRange.lowerBound.line
      let utf16Column = refactorCommand.positionRange.lowerBound.utf16index
      guard let utf8Column = snapshot.lineTable.utf8ColumnAt(line: line, utf16Column: utf16Column) else {
        return completion(.failure(.invalidRange(refactorCommand.positionRange)))
      }

      let skreq = SKDRequestDictionary(sourcekitd: self.sourcekitd)
      skreq[keys.request] = self.requests.semantic_refactoring
      // Preferred name for e.g. an extracted variable.
      // Empty string means sourcekitd chooses a name automatically.
      skreq[keys.name] = ""
      skreq[keys.sourcefile] = uri.pseudoPath
      // LSP is zero based, but this request is 1 based.
      skreq[keys.line] = line + 1
      skreq[keys.column] = utf8Column + 1
      skreq[keys.length] = offsetRange.count
      skreq[keys.actionuid] = self.sourcekitd.api.uid_get_from_cstr(refactorCommand.actionString)!

      // FIXME: SourceKit should probably cache this for us.
      if let compileCommand = self.commandsByFile[snapshot.document.uri] {
        skreq[keys.compilerargs] = compileCommand.compilerArgs
      }

      let handle = self.sourcekitd.send(skreq, self.queue) { [weak self] result in
        guard let self = self else { return }
        guard let dict = result.success else {
          return completion(.failure(.responseError(ResponseError(result.failure!))))
        }
        guard let refactor = SemanticRefactoring(refactorCommand.title, dict, snapshot, self.keys) else {
          return completion(.failure(.noEditsNeeded(uri)))
        }
        completion(.success(refactor))
      }

      // FIXME: cancellation
      _ = handle
    }
  }
}
