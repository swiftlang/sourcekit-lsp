//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CompletionScoring
import XCTest

extension XCTestCase {
  func score(
    patternText: String,
    candidate: SemanticScoredText,
    contenType: Pattern.ContentType = .codeCompletionSymbol,
    precision: Pattern.Precision
  ) -> CompletionScore {
    let textScore = Candidate.withAccessToCandidate(for: candidate.text, contentType: contenType) { candidate in
      Pattern(text: patternText).score(candidate: candidate, precision: precision)
    }
    return CompletionScore(textComponent: textScore, semanticComponent: candidate.semanticScore)
  }

  func test(
    _ patternText: String,
    precision: Pattern.Precision,
    prefers expectedWinner: SemanticScoredText,
    over expectedLoser: SemanticScoredText,
    contentType: Pattern.ContentType = .codeCompletionSymbol
  ) {
    let expectedWinnerScore = score(
      patternText: patternText,
      candidate: expectedWinner,
      contenType: contentType,
      precision: precision
    )
    let expectedLoserScore = score(
      patternText: patternText,
      candidate: expectedLoser,
      contenType: contentType,
      precision: precision
    )
    func failureMessage() -> String {
      formatTable(rows: [
        ["Expected Winner", "Semantic Scores", "Text Score", "Composite Score", "Candidate Text"],
        [
          "✓", expectedWinnerScore.semanticComponent.format(precision: 3),
          expectedWinnerScore.textComponent.format(precision: 3),
          expectedWinnerScore.value.format(precision: 3), expectedWinner.text,
        ],
        [
          "", expectedLoserScore.semanticComponent.format(precision: 3),
          expectedLoserScore.textComponent.format(precision: 3),
          expectedLoserScore.value.format(precision: 3), expectedLoser.text,
        ],
      ])
    }
    XCTAssert(
      expectedWinnerScore > expectedLoserScore,
      "\"\(patternText)\" should match \"\(expectedWinner.text)\" better than \"\(expectedLoser.text)\".\n\(failureMessage())\n"
    )
  }

  func score(
    patternText: String,
    candidateText: String,
    contenType: Pattern.ContentType = .codeCompletionSymbol,
    precision: Pattern.Precision
  ) -> Double {
    score(patternText: patternText, candidate: SemanticScoredText(candidateText), precision: precision)
      .textComponent
  }

  func test(
    _ patternText: String,
    precision: Pattern.Precision,
    prefers expectedWinnerText: String,
    over expectedLoserText: String
  ) {
    test(
      patternText,
      precision: precision,
      prefers: SemanticScoredText(expectedWinnerText),
      over: SemanticScoredText(expectedLoserText)
    )
  }
}

extension String {
  func enumeratePrefixes(includeLowercased: Bool, body: (String) -> Void) {
    for length in 1..<count {
      body(String(prefix(length)))
      if includeLowercased {
        body(String(lowercased().prefix(length)))
      }
    }
  }
}

fileprivate extension Double {
  func format(precision: Int) -> String {
    String(format: "%.0\(precision)f", self)
  }
}

private func formatTable(rows: [[String]]) -> String {
  if let headers = rows.first {
    let separator = " | "
    let headerSeparatorColumnSeparator = "-+-"
    var columnWidths = Array(repeating: 0, count: headers.count)
    for row in rows {
      precondition(row.count == headers.count)
      for (columnIndex, cell) in row.enumerated() {
        columnWidths[columnIndex] = max(columnWidths[columnIndex], cell.count)
      }
    }
    var formatedRows: [String] = rows.map { row in
      let indentedCells: [String] = row.enumerated().map { columnIndex, cell in
        let spacesToAdd = columnWidths[columnIndex] - cell.count
        let indent = String(repeating: " ", count: spacesToAdd)
        return indent + cell
      }
      return indentedCells.joined(separator: separator)
    }
    let headerSeparator = headers.enumerated().map { (columnIndex, _) in
      String(repeating: "-", count: columnWidths[columnIndex])
    }.joined(separator: headerSeparatorColumnSeparator)
    formatedRows.insert(headerSeparator, at: 1)
    return formatedRows.joined(separator: "\n")
  } else {
    return ""
  }
}
