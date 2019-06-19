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
import Basic
import sourcekitd

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
}

extension SemanticRefactoring {

  /// Create a `SemanticRefactoring` from a sourcekitd response dictionary, if possible.
  ///
  /// - Parameters:
  ///   - title: The title of the refactoring action.
  ///   - dict: Response dictionary to extract information from.
  ///   - url: The client URL that triggered the `semantic_refactoring` request.
  ///   - keys: The sourcekitd key set to use for looking up into `dict`.
  init?(_ title: String, _ dict: SKResponseDictionary, _ url: URL, _ keys: sourcekitd_keys) {
    guard let categorizedEdits: SKResponseArray = dict[keys.categorizededits] else {
      // Nothing to report.
      return nil
    }

    var textEdits = [TextEdit]()

    categorizedEdits.forEach { _, value in
      guard let edits: SKResponseArray = value[keys.edits] else {
        return false
      }
      edits.forEach { _, value in
        if let startLine: Int = value[keys.line],
           let startColumn: Int = value[keys.column],
           let endLine: Int = value[keys.endline],
           let endColumn: Int = value[keys.endcolumn],
           let text: String = value[keys.text]
        {
          // The LSP is zero based, but semantic_refactoring is one based.
          let startPosition = Position(line: startLine - 1, utf16index: startColumn - 1)
          let endPosition = Position(line: endLine - 1, utf16index: endColumn - 1)
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
    self.edit = WorkspaceEdit(changes: [url: textEdits])
  }
}

/// An error from a cursor info request.
enum SemanticRefactoringError: Error {

  /// The given URL is not a known document.
  case unknownDocument(URL)

  /// The underlying sourcekitd request failed with the given error.
  case responseError(ResponseError)

  /// The underlying sourcekitd reported no edits for this action.
  case noEditsNeeded(URL)
}

extension SemanticRefactoringError: CustomStringConvertible {
  var description: String {
    switch self {
    case .unknownDocument(let url):
      return "failed to find snapshot for url \(url)"
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
    let url = refactorCommand.textDocument.url
    guard let snapshot = documentManager.latestSnapshot(url) else {
      return completion(.failure(.unknownDocument(url)))
    }
    let skreq = SKRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.semantic_refactoring
    skreq[keys.name] = ""
    skreq[keys.sourcefile] = url.path
    skreq[keys.line] = refactorCommand.line + 1
    skreq[keys.column] = refactorCommand.column + 1 // LSP is zero based, but this request is 1 based.
    skreq[keys.length] = refactorCommand.length
    skreq[keys.actionuid] = sourcekitd.api.uid_get_from_cstr(refactorCommand.actionString)!
    if let settings = buildSystem.settings(for: url, snapshot.document.language) {
      skreq[keys.compilerargs] = settings.compilerArguments
    }

    let handle = sourcekitd.send(skreq) { [weak self] result in
      guard let self = self else { return }
      guard let dict = result.success else {
        return completion(.failure(.responseError(result.failure!)))
      }
      guard let refactor = SemanticRefactoring(refactorCommand.title, dict, url, self.keys) else {
        return completion(.failure(.noEditsNeeded(url)))
      }
      completion(.success(refactor))
    }

    // FIXME: cancellation
    _ = handle
  }
}
