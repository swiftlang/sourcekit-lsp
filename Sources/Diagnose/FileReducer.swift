//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SourceKitD
import SwiftParser
import SwiftSyntax

/// Reduces an input source file while continuing to reproduce the crash
class FileReducer {
  /// The executor that is used to run a sourcekitd request and check whether it
  /// still crashes.
  private let sourcekitdExecutor: SourceKitRequestExecutor

  /// The file to which we write the reduced source code.
  private let temporarySourceFile: URL

  init(sourcekitdExecutor: SourceKitRequestExecutor) {
    self.sourcekitdExecutor = sourcekitdExecutor
    temporarySourceFile = FileManager.default.temporaryDirectory.appendingPathComponent("reduce.swift")
  }

  /// Reduce the file contents in `initialRequest` to a smaller file that still reproduces a crash.
  func run(initialRequestInfo: RequestInfo) async throws -> RequestInfo {
    var requestInfo = initialRequestInfo
    try await validateRequestInfoCrashes(requestInfo: requestInfo)

    requestInfo = try await runReductionStep(requestInfo: requestInfo, reduce: removeComments) ?? requestInfo

    requestInfo = try await runStatefulReductionStep(
      requestInfo: requestInfo,
      reducer: ReplaceFunctionBodiesByFatalError()
    )

    // Run removal of members and code block items in a loop. Sometimes the removal of a code block item further down in the
    // file can remove the last reference to a member which can then be removed as well.
    while true {
      let reducedRequestInfo = try await runStatefulReductionStep(
        requestInfo: requestInfo,
        reducer: RemoveMembersAndCodeBlockItems()
      )
      if reducedRequestInfo.fileContents == requestInfo.fileContents {
        // No changes were made during reduction. We are done.
        break
      }
      requestInfo = reducedRequestInfo
    }

    return requestInfo
  }

  func logSuccessfulReduction(_ requestInfo: RequestInfo) {
    print("Reduced source file to \(requestInfo.fileContents.utf8.count) bytes")
  }

  // MARK: - Running reduction steps

  private func validateRequestInfoCrashes(requestInfo: RequestInfo) async throws {
    let initialReproducer = try await runReductionStep(requestInfo: requestInfo) { tree in [] }
    if initialReproducer == nil {
      throw ReductionError("Initial request info did not crash")
    }
  }

  /// Run a single reduction step.
  ///
  /// If the request still crashes after applying the edits computed by `reduce`, return the reduced request info.
  /// Otherwise, return `nil`
  private func runReductionStep(
    requestInfo: RequestInfo,
    reduce: (_ tree: SourceFileSyntax) throws -> [SourceEdit]
  ) async throws -> RequestInfo? {
    let tree = Parser.parse(source: requestInfo.fileContents)
    let edits = try reduce(tree)
    let reducedSource = FixItApplier.apply(edits: edits, to: tree)

    var adjustedOffset = requestInfo.offset
    for edit in edits {
      if edit.range.upperBound < AbsolutePosition(utf8Offset: requestInfo.offset) {
        adjustedOffset -= (edit.range.upperBound.utf8Offset - edit.range.lowerBound.utf8Offset)
        adjustedOffset += edit.replacement.utf8.count
      }
    }

    let reducedRequestInfo = RequestInfo(
      requestTemplate: requestInfo.requestTemplate,
      offset: adjustedOffset,
      compilerArgs: requestInfo.compilerArgs,
      fileContents: reducedSource
    )

    try reducedSource.write(to: temporarySourceFile, atomically: false, encoding: .utf8)
    let result = try await sourcekitdExecutor.run(request: reducedRequestInfo.request(for: temporarySourceFile))
    if result == .crashed {
      logSuccessfulReduction(reducedRequestInfo)
      return reducedRequestInfo
    } else {
      // The reduced request did not crash. We did not find a reduced test case, so return `nil`.
      return nil
    }
  }

  /// Run a reducer that can carry state between reduction steps.
  ///
  /// This invokes `reduce(tree:)` on `reducer` as long as the `reduce` method returns non-empty edits.
  /// When `reducer.reduce(tree:)` returns empty edits, it indicates that it can't reduce the file any further
  /// and this method return the reduced request info.
  func runStatefulReductionStep(
    requestInfo: RequestInfo,
    reducer: any StatefulReducer
  ) async throws -> RequestInfo {
    /// Error to indicate that `reducer.reduce(tree:)` did not produce any edits.
    /// Will always be caught within the function.
    struct StatefulReducerFinishedReducing: Error {}

    var reproducer = requestInfo
    while true {
      do {
        let reduced = try await runReductionStep(requestInfo: reproducer) { tree in
          let edits = reducer.reduce(tree: tree)
          if edits.isEmpty {
            throw StatefulReducerFinishedReducing()
          }
          return edits
        }
        if let reduced {
          reproducer = reduced
        }
      } catch is StatefulReducerFinishedReducing {
        return reproducer
      }
    }
  }
}

// MARK: - Reduce functions

/// See `FileReducer.runReductionStep`
protocol StatefulReducer {
  func reduce(tree: SourceFileSyntax) -> [SourceEdit]
}

/// Tries replacing one function body by `fatalError()` at a time.
class ReplaceFunctionBodiesByFatalError: StatefulReducer {
  /// The function bodies that should not be replaced by `fatalError()`.
  ///
  /// When we tried replacing a function body by `fatalError`, it gets added to this list.
  /// That way, if replacing it did not result in a reduced reproducer, we won't try replacing it again
  /// on the next invocation of `reduce(tree:)`.
  ///
  /// `fatalError()` is in here from the start to mark functions that we have replaced by `fatalError()` as done.
  /// There's no point replacing a `fatalError()` function by `fatalError()` again.
  var keepFunctionBodies: [String] = ["fatalError()"]

  func reduce(tree: SourceFileSyntax) -> [SourceEdit] {
    let visitor = Visitor(keepFunctionBodies: keepFunctionBodies)
    visitor.walk(tree)
    keepFunctionBodies = visitor.keepFunctionBodies
    return visitor.edits
  }

  private class Visitor: SyntaxAnyVisitor {
    var keepFunctionBodies: [String]
    var edits: [SourceEdit] = []

    init(keepFunctionBodies: [String]) {
      self.keepFunctionBodies = keepFunctionBodies
      super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
      if !edits.isEmpty {
        // We already produced an edit. We only want to replace one function at a time.
        return .skipChildren
      }
      return .visitChildren
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
      if !edits.isEmpty {
        return .skipChildren
      }
      if keepFunctionBodies.contains(node.statements.description.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return .visitChildren
      } else {
        keepFunctionBodies.append(node.statements.description.trimmingCharacters(in: .whitespacesAndNewlines))
        edits.append(
          SourceEdit(
            range: node.statements.position..<node.statements.endPosition,
            replacement: "\(node.statements.leadingTrivia)fatalError()"
          )
        )
        return .skipChildren
      }
    }
  }
}

/// Tries removing `MemberBlockItemSyntax` and `CodeBlockItemSyntax` one at a time.
class RemoveMembersAndCodeBlockItems: StatefulReducer {
  /// The code block items / members that shouldn't be removed.
  ///
  /// See `ReplaceFunctionBodiesByFatalError.keepFunctionBodies`.
  var keepItems: [String] = []

  func reduce(tree: SourceFileSyntax) -> [SourceEdit] {
    let visitor = Visitor(keepMembers: keepItems)
    visitor.walk(tree)
    keepItems = visitor.keepItems
    return visitor.edits
  }

  private class Visitor: SyntaxAnyVisitor {
    var keepItems: [String]
    var edits: [SourceEdit] = []

    init(keepMembers: [String]) {
      self.keepItems = keepMembers
      super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
      if !edits.isEmpty {
        return .skipChildren
      }
      return .visitChildren
    }

    override func visit(_ node: MemberBlockItemSyntax) -> SyntaxVisitorContinueKind {
      if !edits.isEmpty {
        return .skipChildren
      }
      if keepItems.contains(node.description.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return .visitChildren
      } else {
        keepItems.append(node.description.trimmingCharacters(in: .whitespacesAndNewlines))
        edits.append(SourceEdit(range: node.position..<node.endPosition, replacement: ""))
        return .skipChildren
      }
    }

    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
      if !edits.isEmpty {
        return .skipChildren
      }
      if keepItems.contains(node.description.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return .visitChildren
      } else {
        keepItems.append(node.description.trimmingCharacters(in: .whitespacesAndNewlines))
        edits.append(SourceEdit(range: node.position..<node.endPosition, replacement: ""))
        return .skipChildren
      }
    }
  }
}

/// Removes all comments from the source file.
func removeComments(from tree: SourceFileSyntax) -> [SourceEdit] {
  class CommentRemover: SyntaxVisitor {
    var edits: [SourceEdit] = []

    private func removeComments(from trivia: Trivia, startPosition: AbsolutePosition) {
      var position = startPosition
      var previousTriviaPiece: TriviaPiece?
      for triviaPiece in trivia {
        defer {
          previousTriviaPiece = triviaPiece
          position += triviaPiece.sourceLength
        }
        if triviaPiece.isComment || (triviaPiece.isNewline && previousTriviaPiece?.isComment ?? false) {
          edits.append(SourceEdit(range: position..<(position + triviaPiece.sourceLength), replacement: ""))
        }
      }
    }

    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
      removeComments(from: node.leadingTrivia, startPosition: node.position)
      removeComments(from: node.trailingTrivia, startPosition: node.endPositionBeforeTrailingTrivia)
      return .skipChildren
    }
  }

  let remover = CommentRemover(viewMode: .sourceAccurate)
  remover.walk(tree)
  return remover.edits
}

fileprivate extension TriviaPiece {
  var isComment: Bool {
    switch self {
    case .blockComment, .docBlockComment, .docLineComment, .lineComment:
      return true
    default:
      return false
    }
  }
}
