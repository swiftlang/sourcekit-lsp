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

    requestInfo = try await fatalErrorFunctionBodies(requestInfo)
    requestInfo = try await removeMembersAndCodeBlockItemsBodies(requestInfo)
    while let importInlined = try await inlineFirstImport(requestInfo) {
      requestInfo = importInlined
      requestInfo = try await fatalErrorFunctionBodies(requestInfo)
      // Generated interfaces are huge. Try removing multiple consecutive declarations at once
      // before going into fine-grained mode
      requestInfo = try await removeMembersAndCodeBlockItemsBodies(requestInfo, simultaneousRemove: 100)
      requestInfo = try await removeMembersAndCodeBlockItemsBodies(requestInfo, simultaneousRemove: 10)
      requestInfo = try await removeMembersAndCodeBlockItemsBodies(requestInfo)
    }

    requestInfo = try await removeComments(requestInfo)

    return requestInfo
  }

  // MARK: - Reduction steps

  private func validateRequestInfoCrashes(requestInfo: RequestInfo) async throws {
    let initialReproducer = try await runReductionStep(requestInfo: requestInfo) { tree in [] }
    if initialReproducer == nil {
      throw ReductionError("Initial request info did not crash")
    }
  }

  /// Replace function bodies by `fatalError()`
  private func fatalErrorFunctionBodies(_ requestInfo: RequestInfo) async throws -> RequestInfo {
    try await runStatefulReductionStep(
      requestInfo: requestInfo,
      reducer: ReplaceFunctionBodiesByFatalError()
    )
  }

  /// Remove members and code block items.
  ///
  /// When `simultaneousRemove` is set, this automatically removes `simultaneousRemove` number of adjacent items.
  /// This can significantly speed up the reduction of large files with many top-level items.
  private func removeMembersAndCodeBlockItemsBodies(
    _ requestInfo: RequestInfo,
    simultaneousRemove: Int = 1
  ) async throws -> RequestInfo {
    var requestInfo = requestInfo
    // Run removal of members and code block items in a loop. Sometimes the removal of a code block item further down in the
    // file can remove the last reference to a member which can then be removed as well.
    while true {
      let reducedRequestInfo = try await runStatefulReductionStep(
        requestInfo: requestInfo,
        reducer: RemoveMembersAndCodeBlockItems(simultaneousRemove: simultaneousRemove)
      )
      if reducedRequestInfo.fileContents == requestInfo.fileContents {
        // No changes were made during reduction. We are done.
        break
      }
      requestInfo = reducedRequestInfo
    }
    return requestInfo
  }

  /// Remove comments from the source file.
  private func removeComments(_ requestInfo: RequestInfo) async throws -> RequestInfo {
    try await runReductionStep(requestInfo: requestInfo, reduce: removeComments(from:)) ?? requestInfo
  }

  /// Replace the first `import` declaration in the source file by the contents of the Swift interface.
  private func inlineFirstImport(_ requestInfo: RequestInfo) async throws -> RequestInfo? {
    try await runReductionStep(requestInfo: requestInfo) { tree in
      let edits = await Diagnose.inlineFirstImport(
        in: tree,
        executor: sourcekitdExecutor,
        compilerArgs: requestInfo.compilerArgs
      )
      return edits
    }
  }

  // MARK: - Primitives to run reduction steps

  func logSuccessfulReduction(_ requestInfo: RequestInfo) {
    print("Reduced source file to \(requestInfo.fileContents.utf8.count) bytes")
  }

  /// Run a single reduction step.
  ///
  /// If the request still crashes after applying the edits computed by `reduce`, return the reduced request info.
  /// Otherwise, return `nil`
  private func runReductionStep(
    requestInfo: RequestInfo,
    reduce: (_ tree: SourceFileSyntax) async throws -> [SourceEdit]?
  ) async throws -> RequestInfo? {
    let tree = Parser.parse(source: requestInfo.fileContents)
    guard let edits = try await reduce(tree) else {
      return nil
    }
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
    if case .reproducesIssue = result {
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

// MARK: Replace function bodies

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

// MARK: Remove members and code block items

/// Tries removing `MemberBlockItemSyntax` and `CodeBlockItemSyntax` one at a time.
class RemoveMembersAndCodeBlockItems: StatefulReducer {
  /// The code block items / members that shouldn't be removed.
  ///
  /// See `ReplaceFunctionBodiesByFatalError.keepFunctionBodies`.
  var keepItems: [String] = []

  let simultaneousRemove: Int

  init(simultaneousRemove: Int) {
    self.simultaneousRemove = simultaneousRemove
  }

  func reduce(tree: SourceFileSyntax) -> [SourceEdit] {
    let visitor = Visitor(keepMembers: keepItems, maxEdits: simultaneousRemove)
    visitor.walk(tree)
    keepItems = visitor.keepItems
    return visitor.edits
  }

  private class Visitor: SyntaxAnyVisitor {
    var keepItems: [String]
    var edits: [SourceEdit] = []
    let maxEdits: Int

    init(keepMembers: [String], maxEdits: Int) {
      self.keepItems = keepMembers
      self.maxEdits = maxEdits
      super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
      if edits.count >= maxEdits {
        return .skipChildren
      }
      return .visitChildren
    }

    override func visit(_ node: MemberBlockItemSyntax) -> SyntaxVisitorContinueKind {
      if edits.count >= maxEdits {
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
      if edits.count >= maxEdits {
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

// MARK: Inline first include

class FirstImportFinder: SyntaxAnyVisitor {
  var firstImport: ImportDeclSyntax?

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if firstImport == nil {
      return .visitChildren
    } else {
      return .skipChildren
    }
  }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    if firstImport == nil {
      firstImport = node
    }
    return .skipChildren
  }

  static func findFirstImport(in tree: some SyntaxProtocol) -> ImportDeclSyntax? {
    let visitor = FirstImportFinder(viewMode: .sourceAccurate)
    visitor.walk(tree)
    return visitor.firstImport
  }
}

private func getSwiftInterface(_ moduleName: String, executor: SourceKitRequestExecutor, compilerArgs: [String])
  async throws -> String
{
  // FIXME: Use the sourcekitd specified on the command line once rdar://121676425 is fixed
  let sourcekitdPath =
    "/Applications/Geode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitdInProc.framework/sourcekitdInProc"
  let executor = SourceKitRequestExecutor(
    sourcekitd: URL(fileURLWithPath: sourcekitdPath),
    reproducerPredicate: nil
  )

  // We use `RequestInfo` and its template to add the compiler arguments to the request.
  let requestTemplate = """
    {
      key.request: source.request.editor.open.interface,
      key.name: "fake",
      key.compilerargs: [
        $COMPILERARGS
      ],
      key.modulename: "\(moduleName)"
    }
    """
  let requestInfo = RequestInfo(
    requestTemplate: requestTemplate,
    offset: 0,
    compilerArgs: compilerArgs,
    fileContents: ""
  )
  let request = try requestInfo.request(for: URL(fileURLWithPath: "/"))

  guard case .success(let result) = try await executor.run(request: request) else {
    throw ReductionError("Failed to get Swift Interface for \(moduleName)")
  }

  // Extract the line containing the source text and parse that using JSON decoder.
  // We can't parse the entire response using `JSONEncoder` because the sourcekitd response isn't actually valid JSON
  // (it doesn't quote keys, for example). So, extract the string, which is actually correctly JSON encoded.
  let quotedSourceText = result.components(separatedBy: "\n").compactMap { (line) -> Substring? in
    let prefix = "  key.sourcetext: "
    guard line.hasPrefix(prefix) else {
      return nil
    }
    var line: Substring = line[...]
    line = line.dropFirst(prefix.count)
    if line.hasSuffix(",") {
      line = line.dropLast()
    }
    return line
  }.only
  guard let quotedSourceText else {
    throw ReductionError("Failed to decode Swift interface response for \(moduleName)")
  }
  // Filter control characters. JSONDecoder really doensn't like them and they are likely not important if they occur eg. in a comment.
  let sanitizedData = Data(quotedSourceText.utf8.filter { $0 >= 32 })
  return try JSONDecoder().decode(String.self, from: sanitizedData)
}

func inlineFirstImport(
  in tree: SourceFileSyntax,
  executor: SourceKitRequestExecutor,
  compilerArgs: [String]
) async -> [SourceEdit]? {
  guard let firstImport = FirstImportFinder.findFirstImport(in: tree) else {
    return nil
  }
  guard let moduleName = firstImport.path.only?.name else {
    return nil
  }
  guard let interface = try? await getSwiftInterface(moduleName.text, executor: executor, compilerArgs: compilerArgs)
  else {
    return nil
  }
  let edit = SourceEdit(range: firstImport.position..<firstImport.endPosition, replacement: interface)
  return [edit]
}
