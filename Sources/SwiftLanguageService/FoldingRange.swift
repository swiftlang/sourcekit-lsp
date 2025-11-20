//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SKUtilities
import SourceKitLSP
import SwiftSyntax

private final class FoldingRangeFinder: SyntaxAnyVisitor {
  private let snapshot: DocumentSnapshot
  /// Some ranges might occur multiple times.
  /// E.g. for `print("hi")`, `"hi"` is both the range of all call arguments and the range the first argument in the call.
  /// It doesn't make sense to report them multiple times, so use a `Set` here.
  private var ranges: Set<FoldingRange>
  /// The client-imposed limit on the number of folding ranges it would
  /// prefer to receive from the LSP server. If the value is `nil`, there
  /// is no preset limit.
  private var rangeLimit: Int?
  /// If `true`, the client is only capable of folding entire lines. If
  /// `false` the client can handle folding ranges.
  private var lineFoldingOnly: Bool

  init(snapshot: DocumentSnapshot, rangeLimit: Int?, lineFoldingOnly: Bool) {
    self.snapshot = snapshot
    self.ranges = []
    self.rangeLimit = rangeLimit
    self.lineFoldingOnly = lineFoldingOnly
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
    // Index comments, so we need to see at least '/*', or '//'.
    if node.leadingTriviaLength.utf8Length > 2 {
      self.addTrivia(from: node, node.leadingTrivia)
    }

    if node.trailingTriviaLength.utf8Length > 2 {
      self.addTrivia(from: node, node.trailingTrivia)
    }

    return .visitChildren
  }

  private func addTrivia(from node: TokenSyntax, _ trivia: Trivia) {
    let pieces = trivia.pieces
    var start = node.position
    /// The index of the trivia piece we are currently inspecting.
    var index = 0

    while index < pieces.count {
      let piece = pieces[index]
      defer {
        start = start.advanced(by: pieces[index].sourceLength.utf8Length)
        index += 1
      }
      switch piece {
      case .blockComment:
        _ = self.addFoldingRange(
          start: start,
          end: start.advanced(by: piece.sourceLength.utf8Length),
          kind: .comment
        )
      case .docBlockComment:
        _ = self.addFoldingRange(
          start: start,
          end: start.advanced(by: piece.sourceLength.utf8Length),
          kind: .comment
        )
      case .lineComment, .docLineComment:
        let lineCommentBlockStart = start

        // Keep scanning the upcoming trivia pieces to find the end of the
        // block of line comments.
        // As we find a new end of the block comment, we set `index` and
        // `start` to `lookaheadIndex` and `lookaheadStart` resp. to
        // commit the newly found end.
        var lookaheadIndex = index
        var lookaheadStart = start
        var hasSeenNewline = false
        LOOP: while lookaheadIndex < pieces.count {
          let piece = pieces[lookaheadIndex]
          defer {
            lookaheadIndex += 1
            lookaheadStart = lookaheadStart.advanced(by: piece.sourceLength.utf8Length)
          }
          switch piece {
          case .newlines(let count), .carriageReturns(let count), .carriageReturnLineFeeds(let count):
            if count > 1 || hasSeenNewline {
              // More than one newline is separating the two line comment blocks.
              // We have reached the end of this block of line comments.
              break LOOP
            }
            hasSeenNewline = true
          case .spaces, .tabs:
            // We allow spaces and tabs because the comments might be indented
            continue
          case .lineComment, .docLineComment:
            // We have found a new line comment in this block. Commit it.
            index = lookaheadIndex
            start = lookaheadStart
            hasSeenNewline = false
          default:
            // We assume that any other trivia piece terminates the block
            // of line comments.
            break LOOP
          }
        }
        _ = self.addFoldingRange(
          start: lineCommentBlockStart,
          end: start.advanced(by: pieces[index].sourceLength.utf8Length),
          kind: .comment
        )
      default:
        break
      }
    }
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if let braced = node.asProtocol((any BracedSyntax).self) {
      return self.addFoldingRange(
        start: braced.leftBrace.endPositionBeforeTrailingTrivia,
        end: braced.rightBrace.positionAfterSkippingLeadingTrivia
      )
    }
    if let parenthesized = node.asProtocol((any ParenthesizedSyntax).self) {
      return self.addFoldingRange(
        start: parenthesized.leftParen.endPositionBeforeTrailingTrivia,
        end: parenthesized.rightParen.positionAfterSkippingLeadingTrivia
      )
    }
    return .visitChildren
  }

  override func visit(_ node: ArrayExprSyntax) -> SyntaxVisitorContinueKind {
    return self.addFoldingRange(
      start: node.leftSquare.endPositionBeforeTrailingTrivia,
      end: node.rightSquare.positionAfterSkippingLeadingTrivia
    )
  }

  override func visit(_ node: DictionaryExprSyntax) -> SyntaxVisitorContinueKind {
    return self.addFoldingRange(
      start: node.leftSquare.endPositionBeforeTrailingTrivia,
      end: node.rightSquare.positionAfterSkippingLeadingTrivia
    )
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    if let leftParen = node.leftParen, let rightParen = node.rightParen {
      return self.addFoldingRange(
        start: leftParen.endPositionBeforeTrailingTrivia,
        end: rightParen.positionAfterSkippingLeadingTrivia
      )
    }
    return .visitChildren
  }

  override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
    guard let closePound = node.lastToken(viewMode: .sourceAccurate)?.nextToken(viewMode: .sourceAccurate) else {
      return .visitChildren
    }

    return self.addFoldingRange(
      start: node.poundKeyword.positionAfterSkippingLeadingTrivia,
      end: closePound.positionAfterSkippingLeadingTrivia
    )
  }

  override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
    return self.addFoldingRange(
      start: node.leftSquare.endPositionBeforeTrailingTrivia,
      end: node.rightSquare.positionAfterSkippingLeadingTrivia
    )
  }

  override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
    return self.addFoldingRange(
      start: node.label.endPositionBeforeTrailingTrivia,
      end: node.statements.endPosition
    )
  }

  __consuming func finalize() -> Set<FoldingRange> {
    return self.ranges
  }

  private func addFoldingRange(
    start: AbsolutePosition,
    end: AbsolutePosition,
    kind: FoldingRangeKind? = nil
  ) -> SyntaxVisitorContinueKind {
    if let limit = self.rangeLimit, self.ranges.count >= limit {
      return .skipChildren
    }
    if start == end {
      // Don't report empty ranges
      return .visitChildren
    }

    let start = snapshot.positionOf(utf8Offset: start.utf8Offset)
    let end = snapshot.positionOf(utf8Offset: end.utf8Offset)
    let range: FoldingRange
    if lineFoldingOnly {
      // If the folding range doesn't end at the end of the last line, exclude that line from the folding range since
      // the end line gets folded away. This means if we reported `end.line`, we would eg. fold away the `}` that
      // matches a `{`, which looks surprising.
      // If the folding range does end at the end of the line we are in cases that don't have a closing indicator (like
      // comments), so we can fold the last line as well.
      let endLine: Int
      if snapshot.lineTable.isAtEndOfLine(end) {
        endLine = end.line
      } else {
        endLine = end.line - 1
      }

      // Since the client cannot fold less than a single line, if the
      // fold would span 1 line there's no point in reporting it.
      guard endLine > start.line else {
        return .visitChildren
      }

      // If the client only supports folding full lines, don't report
      // the end of the range since there's nothing they could do with it.
      range = FoldingRange(
        startLine: start.line,
        startUTF16Index: nil,
        endLine: endLine,
        endUTF16Index: nil,
        kind: kind
      )
    } else {
      range = FoldingRange(
        startLine: start.line,
        startUTF16Index: start.utf16index,
        endLine: end.line,
        endUTF16Index: end.utf16index,
        kind: kind
      )
    }
    ranges.insert(range)
    return .visitChildren
  }
}

extension SwiftLanguageService {
  package func foldingRange(_ req: FoldingRangeRequest) async throws -> [FoldingRange]? {
    let foldingRangeCapabilities = capabilityRegistry.clientCapabilities.textDocument?.foldingRange
    let snapshot = try self.documentManager.latestSnapshot(req.textDocument.uri)

    let sourceFile = await syntaxTreeManager.syntaxTree(for: snapshot)

    try Task.checkCancellation()

    // If the limit is less than one, do nothing.
    if let limit = foldingRangeCapabilities?.rangeLimit, limit <= 0 {
      return []
    }

    let rangeFinder = FoldingRangeFinder(
      snapshot: snapshot,
      rangeLimit: foldingRangeCapabilities?.rangeLimit,
      lineFoldingOnly: foldingRangeCapabilities?.lineFoldingOnly ?? false
    )
    rangeFinder.walk(sourceFile)
    let ranges = rangeFinder.finalize()

    return ranges.sorted()
  }
}

fileprivate extension LineTable {
  func isAtEndOfLine(_ position: Position) -> Bool {
    guard let line = self.line(at: position.line) else {
      return false
    }
    guard let index = line.utf16.index(line.startIndex, offsetBy: position.utf16index, limitedBy: line.endIndex) else {
      return false
    }
    return line[index...].allSatisfy(\.isNewline)
  }
}
