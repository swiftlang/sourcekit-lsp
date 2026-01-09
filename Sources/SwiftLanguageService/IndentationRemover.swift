//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftSyntax

/// SyntaxRewriter that removes indentation for lines starting with a newline.
class IndentationRemover: SyntaxRewriter {
  private let indentationToRemove: Trivia

  init(indentation: Trivia) {
    self.indentationToRemove = indentation
    super.init(viewMode: .sourceAccurate)
  }

  func rewrite<T: SyntaxProtocol>(_ node: T) -> T {
    return super.rewrite(Syntax(node)).cast(T.self)
  }

  override func visit(_ token: TokenSyntax) -> TokenSyntax {
    var pieces = Array(token.leadingTrivia)

    // Pass 1: Adjust indentation after newlines
    var i = 0
    while i < pieces.count {
      if pieces[i].isNewline {
        // Normalize all newlines to \n to match expected output in tests and
        // common SourceKit-LSP behavior.
        pieces[i] = .newlines(1)
        i += 1

        let pattern = indentationToRemove.pieces
        var piecesToRemove = 0
        var lastPieceAdjusted: TriviaPiece? = nil
        var matched = true

        for p in pattern {
          if i + piecesToRemove >= pieces.count {
            matched = false
            break
          }
          let c = pieces[i + piecesToRemove]
          if p == c {
            piecesToRemove += 1
          } else {
            switch (p, c) {
            case (.spaces(let pn), .spaces(let cn)) where cn >= pn:
              lastPieceAdjusted = .spaces(cn - pn)
              piecesToRemove += 1
            case (.tabs(let pn), .tabs(let cn)) where cn >= pn:
              lastPieceAdjusted = .tabs(cn - pn)
              piecesToRemove += 1
            default:
              matched = false
            }
            break
          }
        }

        if matched {
          if let adjusted = lastPieceAdjusted {
            pieces.removeSubrange(i..<(i + piecesToRemove - 1))
            let isZero: Bool
            switch adjusted {
            case .spaces(0), .tabs(0): isZero = true
            default: isZero = false
            }
            if isZero {
              pieces.remove(at: i)
            } else {
              pieces[i] = adjusted
              i += 1
            }
          } else {
            pieces.removeSubrange(i..<(i + piecesToRemove))
          }
        }
      } else {
        i += 1
      }
    }

    // Pass 2: Adjust internal block comment content
    for j in 0..<pieces.count {
      if case .blockComment(let text) = pieces[j] {
        pieces[j] = .blockComment(removeInternalIndentation(from: text))
      }
    }

    return token.with(\.leadingTrivia, Trivia(pieces: pieces))
  }

  private func removeInternalIndentation(from text: String) -> String {
    let lines = text.components(separatedBy: .newlines)
    guard lines.count > 1 else { return text }

    var adjustedLines: [String] = [lines[0]]
    for line in lines.dropFirst() {
      var adjustedLine = line
      let pattern = indentationToRemove.description
      if adjustedLine.hasPrefix(pattern) {
        adjustedLine.removeFirst(pattern.count)
      }
      adjustedLines.append(adjustedLine)
    }
    return adjustedLines.joined(separator: "\n")
  }
}
