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
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SwiftExtensions
@_spi(FixItApplier) import SwiftIDEUtils
import SwiftParser
import SwiftSyntax

// MARK: - Entry point

extension RequestInfo {
  @MainActor
  package func reduceInputFile(
    using executor: any SourceKitRequestExecutor,
    progressUpdate: (_ progress: Double, _ message: String) -> Void
  ) async throws -> RequestInfo {
    try await withoutActuallyEscaping(progressUpdate) { progressUpdate in
      let reducer = SourceReducer(sourcekitdExecutor: executor, progressUpdate: progressUpdate)
      return try await reducer.run(initialRequestInfo: self)
    }
  }
}

// MARK: - SourceReducer

/// The return value of a source reducer, indicating whether edits were made or if the reducer has finished reducing
/// the source file.
private enum ReducerResult {
  /// The reduction step produced edits that should be applied to the source file.
  case edits([SourceEdit])

  ///  The reduction step was not able to produce any further modifications to the source file. Reduction is done.
  case done

  init(doneIfEmpty edits: [SourceEdit]) {
    if edits.isEmpty {
      self = .done
    } else {
      self = .edits(edits)
    }
  }
}

/// The return value of `runReductionStep`, indicating whether applying the edits from a reducer reduced the issue,
/// failed to reproduce the issue or if no changes were applied by the reducer.
private enum ReductionStepResult {
  case reduced(RequestInfo)
  case didNotReproduce
  case noChange
}

/// Reduces an input source file while continuing to reproduce the crash
@MainActor
private class SourceReducer {
  /// The executor that is used to run a sourcekitd request and check whether it
  /// still crashes.
  private let sourcekitdExecutor: any SourceKitRequestExecutor

  /// A callback to call to report progress
  private let progressUpdate: (_ progress: Double, _ message: String) -> Void

  /// The number of import declarations that the file had when the source reducer was started.
  private var initialImportCount: Int = 0

  /// The byte size of the file when source reduction was started. This gets reset every time an import gets inlined.
  private var fileSizeAfterLastImportInline: Int = 0

  init(
    sourcekitdExecutor: any SourceKitRequestExecutor,
    progressUpdate: @escaping (_ progress: Double, _ message: String) -> Void
  ) {
    self.sourcekitdExecutor = sourcekitdExecutor
    self.progressUpdate = progressUpdate
  }

  /// Reduce the file contents in `initialRequest` to a smaller file that still reproduces a crash.
  @MainActor
  func run(initialRequestInfo: RequestInfo) async throws -> RequestInfo {
    var requestInfo = initialRequestInfo
    self.initialImportCount = Parser.parse(source: requestInfo.fileContents).numberOfImports
    self.fileSizeAfterLastImportInline = initialRequestInfo.fileContents.utf8.count

    try await validateRequestInfoReproducesIssue(requestInfo: requestInfo)

    requestInfo = try await mergeDuplicateTopLevelItems(requestInfo)
    requestInfo = try await removeTopLevelItems(requestInfo)
    requestInfo = try await removeFunctionBodies(requestInfo)
    requestInfo = try await removeMembersAndCodeBlockItemsBodies(requestInfo)
    while let importInlined = try await inlineFirstImport(requestInfo) {
      requestInfo = importInlined
      requestInfo = try await removeTopLevelItems(requestInfo)
      requestInfo = try await removeFunctionBodies(requestInfo)
      requestInfo = try await removeMembersAndCodeBlockItemsBodies(requestInfo)
    }

    requestInfo = try await removeComments(requestInfo)

    return requestInfo
  }

  // MARK: Reduction steps

  private func validateRequestInfoReproducesIssue(requestInfo: RequestInfo) async throws {
    let reductionResult = try await runReductionStep(requestInfo: requestInfo) { tree in .edits([]) }
    switch reductionResult {
    case .reduced:
      break
    case .didNotReproduce:
      throw GenericError("Initial request info did not reproduce the issue")
    case .noChange:
      preconditionFailure("The reduction step always returns empty edits and not `done` so we shouldn't hit this")
    }
  }

  /// Remove the bodies of functions by an empty body.
  private func removeFunctionBodies(_ requestInfo: RequestInfo) async throws -> RequestInfo {
    try await runStatefulReductionStep(
      requestInfo: requestInfo,
      reducer: RemoveFunctionBodies()
    )
  }

  /// Merge any top level items. These can happen if eg. the frontend reducer merged multiple files into one, resulting
  /// in duplicate import statements. Merging these is important because `RemoveTopLevelItems` keeps track of nodes
  /// that have already been visited by node contents and thus fails to remove multiple occurrences of the same import
  /// statement in one go.
  private func mergeDuplicateTopLevelItems(_ requestInfo: RequestInfo) async throws -> RequestInfo {
    let reductionResult = try await runReductionStep(requestInfo: requestInfo, reduce: mergeDuplicateTopLevelItems(in:))
    switch reductionResult {
    case .reduced(let reducedRequestInfo):
      return reducedRequestInfo
    case .didNotReproduce, .noChange:
      return requestInfo
    }
  }

  /// Removes top level items in the source file.
  private func removeTopLevelItems(_ requestInfo: RequestInfo) async throws -> RequestInfo {
    var requestInfo = requestInfo

    // Try removing multiple top-level items at once first. This is useful eg. after inlining a Swift interface or after
    // merging .swift files. Once that's done, go into a more fine-grained mode.
    for simultaneousRemove in [100, 10, 1] {
      let reducedRequestInfo = try await runStatefulReductionStep(
        requestInfo: requestInfo,
        reducer: RemoveTopLevelItems(simultaneousRemove: simultaneousRemove)
      )
      requestInfo = reducedRequestInfo
    }
    return requestInfo
  }

  /// Remove members and code block items.
  ///
  /// When `simultaneousRemove` is set, this automatically removes `simultaneousRemove` number of adjacent items.
  /// This can significantly speed up the reduction of large files with many top-level items.
  private func removeMembersAndCodeBlockItemsBodies(
    _ requestInfo: RequestInfo
  ) async throws -> RequestInfo {
    var requestInfo = requestInfo
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

  /// Remove comments from the source file.
  private func removeComments(_ requestInfo: RequestInfo) async throws -> RequestInfo {
    let reductionResult = try await runReductionStep(requestInfo: requestInfo, reduce: removeComments(from:))
    switch reductionResult {
    case .reduced(let reducedRequestInfo):
      return reducedRequestInfo
    case .didNotReproduce, .noChange:
      return requestInfo
    }
  }

  /// Replace the first `import` declaration in the source file by the contents of the Swift interface.
  private func inlineFirstImport(_ requestInfo: RequestInfo) async throws -> RequestInfo? {
    // Don't report progress after inlining an import because it might increase the file size before we have a chance
    // to increase `fileSizeAfterLastImportInline`. Progress will get updated again on the next successful reduction
    // step.
    let reductionResult = try await runReductionStep(requestInfo: requestInfo, reportProgress: false) { tree in
      let edits = await Diagnose.inlineFirstImport(
        in: tree,
        executor: sourcekitdExecutor,
        compilerArgs: requestInfo.compilerArgs
      )
      return edits
    }
    switch reductionResult {
    case .reduced(let requestInfo):
      self.fileSizeAfterLastImportInline = requestInfo.fileContents.utf8.count
      return requestInfo
    case .didNotReproduce, .noChange:
      return nil
    }
  }

  // MARK: Primitives to run reduction steps

  private func logSuccessfulReduction(_ requestInfo: RequestInfo, tree: SourceFileSyntax) {
    // The number of imports can grow if inlining a single module adds more than 1 new import.
    // To keep progress between 0 and 1, clamp the number of imports to the initial import count.
    let numberOfImports = min(tree.numberOfImports, initialImportCount)
    let fileSize = requestInfo.fileContents.utf8.count

    let progressPerRemovedImport = Double(1) / Double(initialImportCount + 1)
    let removeImportProgress = Double(initialImportCount - numberOfImports) * progressPerRemovedImport
    let fileReductionProgress =
      (1 - Double(fileSize) / Double(fileSizeAfterLastImportInline)) * progressPerRemovedImport
    var progress = removeImportProgress + fileReductionProgress
    if progress < 0 || progress > 1 {
      logger.fault(
        "Trying to report progress \(progress) from remove import progress \(removeImportProgress) and file reduction progress \(fileReductionProgress)"
      )
      progress = max(min(progress, 1), 0)
    }
    progressUpdate(progress, "Reduced to \(numberOfImports) imports and \(fileSize) bytes")
  }

  /// Run a single reduction step.
  ///
  /// If the request still crashes after applying the edits computed by `reduce`, return the reduced request info.
  /// Otherwise, return `nil`
  @MainActor
  private func runReductionStep(
    requestInfo: RequestInfo,
    reportProgress: Bool = true,
    reduce: (_ tree: SourceFileSyntax) async throws -> ReducerResult
  ) async throws -> ReductionStepResult {
    let tree = Parser.parse(source: requestInfo.fileContents)
    let edits: [SourceEdit]
    switch try await reduce(tree) {
    case .edits(let edit): edits = edit
    case .done: return .noChange
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
      contextualRequestTemplates: requestInfo.contextualRequestTemplates,
      offset: adjustedOffset,
      compilerArgs: requestInfo.compilerArgs,
      fileContents: reducedSource
    )

    logger.debug("Try reduction to the following input file:\n\(reducedSource)")
    let result = try await sourcekitdExecutor.run(request: reducedRequestInfo)
    if case .reproducesIssue = result {
      logger.debug("Reduction successful")
      if reportProgress {
        logSuccessfulReduction(reducedRequestInfo, tree: tree)
      }
      return .reduced(reducedRequestInfo)
    } else {
      logger.debug("Reduction did not reproduce the issue")
      return .didNotReproduce
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
      let reduced = try await runReductionStep(requestInfo: reproducer) { tree in
        return reducer.reduce(tree: tree)
      }
      switch reduced {
      case .reduced(let reduced):
        reproducer = reduced
      case .didNotReproduce:
        // Continue the loop and run the reducer again.
        break
      case .noChange:
        // The reducer finished reducing the source file. We are done
        return reproducer
      }
    }
  }
}

// MARK: - Reduce functions

/// See `SourceReducer.runReductionStep`
private protocol StatefulReducer {
  func reduce(tree: SourceFileSyntax) -> ReducerResult
}

// MARK: Remove function bodies

/// Tries removing the contents of function bodies one at a time.
private class RemoveFunctionBodies: StatefulReducer {
  /// The function bodies that should not be removed.
  ///
  /// When we tried removing a function, it gets added to this list.
  /// That way, if replacing it did not result in a reduced reproducer, we won't try replacing it again
  /// on the next invocation of `reduce(tree:)`.
  var keepFunctionBodies: [String] = []

  func reduce(tree: SourceFileSyntax) -> ReducerResult {
    let visitor = Visitor(keepFunctionBodies: keepFunctionBodies)
    visitor.walk(tree)
    keepFunctionBodies = visitor.keepFunctionBodies
    return ReducerResult(doneIfEmpty: visitor.edits)
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
      guard node.statements.count > 0 else {
        return .skipChildren
      }
      if keepFunctionBodies.contains(node.statements.description.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return .visitChildren
      }
      keepFunctionBodies.append(node.statements.description.trimmingCharacters(in: .whitespacesAndNewlines))
      edits.append(
        SourceEdit(
          range: node.statements.position..<node.statements.endPosition,
          replacement: ""
        )
      )
      return .skipChildren
    }
  }
}

// MARK: Remove top level items

/// Tries removing top level items in the source file.
///
/// If `simultaneousRemove` is set, it tries to remove that many adjacent top-level items at a time to quickly reduce
/// the source file.
private class RemoveTopLevelItems: StatefulReducer {
  /// The code block items that shouldn't be removed.
  ///
  /// See `ReplaceFunctionBodiesByFatalError.keepFunctionBodies`.
  var keepItems: [String] = []

  let simultaneousRemove: Int

  init(simultaneousRemove: Int) {
    self.simultaneousRemove = simultaneousRemove
  }

  func reduce(tree: SourceFileSyntax) -> ReducerResult {
    if tree.statements.count <= simultaneousRemove {
      // There are fewer top-level items in the source file than we want to remove. Since removing everything in the
      // source file is very unlikely to be successful, we are done.
      return .done
    }
    let visitor = Visitor(keepMembers: keepItems, maxEdits: simultaneousRemove)
    visitor.walk(tree)
    keepItems = visitor.keepItems
    return ReducerResult(doneIfEmpty: visitor.edits)
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
      guard edits.count < maxEdits else {
        return .skipChildren
      }
      return .visitChildren
    }

    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
      guard node.parent?.parent?.is(SourceFileSyntax.self) ?? false else {
        return .skipChildren
      }
      guard edits.count < maxEdits else {
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

// MARK: Remove members and code block items

/// Tries removing `MemberBlockItemSyntax` and `CodeBlockItemSyntax` one at a time.
private class RemoveMembersAndCodeBlockItems: StatefulReducer {
  /// The code block items / members that shouldn't be removed.
  ///
  /// See `ReplaceFunctionBodiesByFatalError.keepFunctionBodies`.
  var keepItems: [String] = []

  func reduce(tree: SourceFileSyntax) -> ReducerResult {
    let visitor = Visitor(keepMembers: keepItems)
    visitor.walk(tree)
    keepItems = visitor.keepItems
    return ReducerResult(doneIfEmpty: visitor.edits)
  }

  private class Visitor: SyntaxAnyVisitor {
    var keepItems: [String]
    var edits: [SourceEdit] = []

    init(keepMembers: [String]) {
      self.keepItems = keepMembers
      super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
      guard edits.isEmpty else {
        return .skipChildren
      }
      return .visitChildren
    }

    override func visit(_ node: MemberBlockItemSyntax) -> SyntaxVisitorContinueKind {
      guard edits.isEmpty else {
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
      guard edits.isEmpty else {
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

/// For any top-level items in the source file that occur multiple times, only keep the first occurrence.
private func mergeDuplicateTopLevelItems(in tree: SourceFileSyntax) -> ReducerResult {
  class DuplicateTopLevelItemMerger: SyntaxVisitor {
    var seenItems: Set<String> = []
    var edits: [SourceEdit] = []

    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
      guard node.parent?.parent?.is(SourceFileSyntax.self) ?? false else {
        return .skipChildren
      }
      if !seenItems.insert(node.trimmedDescription).inserted {
        edits.append(
          SourceEdit(
            range: node.positionAfterSkippingLeadingTrivia..<node.endPositionBeforeTrailingTrivia,
            replacement: ""
          )
        )
      }
      return .skipChildren
    }
  }

  let remover = DuplicateTopLevelItemMerger(viewMode: .sourceAccurate)
  remover.walk(tree)
  return .edits(remover.edits)
}

/// Removes all comments from the source file.
private func removeComments(from tree: SourceFileSyntax) -> ReducerResult {
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
  return .edits(remover.edits)
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

private class FirstImportFinder: SyntaxAnyVisitor {
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

/// Return the generated interface of the given module.
///
/// `compilerArgs` are the compiler args used to generate the interface. Initially these are the compiler arguments of
/// the file that imports the module. If `areFallbackArgs` is set, we have synthesized fallback arguments that only
/// contain a target and SDK. This is useful when reducing a swift-frontend crash because sourcekitd requires driver
/// arguments but the swift-frontend crash has frontend args.
@MainActor
private func getSwiftInterface(
  _ moduleName: String,
  executor: any SourceKitRequestExecutor,
  compilerArgs: [String],
  areFallbackArgs: Bool = false
) async throws -> String {
  // We use `RequestInfo` and its template to add the compiler arguments to the request.
  let requestTemplate = """
    {
      key.request: source.request.editor.open.interface,
      key.name: "fake",
      key.compilerargs: [
        $COMPILER_ARGS
      ],
      key.modulename: "\(moduleName)"
    }
    """
  let requestInfo = RequestInfo(
    requestTemplate: requestTemplate,
    contextualRequestTemplates: [],
    offset: 0,
    compilerArgs: compilerArgs,
    fileContents: ""
  )

  let result: String
  switch try await executor.run(request: requestInfo) {
  case .success(let response):
    result = response
  case .error where !areFallbackArgs:
    var fallbackArgs: [String] = []
    var argsIterator = compilerArgs.makeIterator()
    while let arg = argsIterator.next() {
      if arg == "-target" || arg == "-sdk" {
        fallbackArgs.append(arg)
        if let value = argsIterator.next() {
          fallbackArgs.append(value)
        }
      }
    }
    return try await getSwiftInterface(
      moduleName,
      executor: executor,
      compilerArgs: fallbackArgs,
      areFallbackArgs: true
    )
  default:
    throw GenericError("Failed to get Swift Interface for \(moduleName)")
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
    throw GenericError("Failed to decode Swift interface response for \(moduleName)")
  }
  // Filter control characters. JSONDecoder really doensn't like them and they are likely not important if they occur eg. in a comment.
  let sanitizedData = Data(quotedSourceText.utf8.filter { $0 >= 32 })
  return try JSONDecoder().decode(String.self, from: sanitizedData)
}

@MainActor
private func inlineFirstImport(
  in tree: SourceFileSyntax,
  executor: any SourceKitRequestExecutor,
  compilerArgs: [String]
) async -> ReducerResult {
  guard let firstImport = FirstImportFinder.findFirstImport(in: tree) else {
    return .done
  }
  guard let moduleName = firstImport.path.only?.name else {
    return .done
  }
  guard let interface = try? await getSwiftInterface(moduleName.text, executor: executor, compilerArgs: compilerArgs)
  else {
    return .done
  }
  let edit = SourceEdit(range: firstImport.position..<firstImport.endPosition, replacement: interface)
  return .edits([edit])
}

fileprivate extension SourceFileSyntax {
  var numberOfImports: Int {
    // If a module is imported multiple times (eg. because we merged .swift files), only count it once.
    let importedModules = self.statements.compactMap { $0.item.as(ImportDeclSyntax.self)?.path.trimmedDescription }
    return Set(importedModules).count
  }
}
