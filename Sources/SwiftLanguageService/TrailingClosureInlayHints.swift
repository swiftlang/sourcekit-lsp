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
@_spi(SourceKitLSP) package import LanguageServerProtocol
package import SKOptions
import SourceKitD
import SourceKitLSP
import SwiftSyntax

/// Collects trailing closure inlay hints for function calls.
private class TrailingClosureHintCollector: SyntaxVisitor {
  private var hints: [TrailingClosureHintInfo] = []

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    if let trailingClosure = node.trailingClosure {
      let hintInfo = TrailingClosureHintInfo(
        trailingClosure: trailingClosure,
        functionCall: node
      )
      hints.append(hintInfo)
    }
    return .visitChildren
  }

  static func collectTrailingClosures(in tree: some SyntaxProtocol) -> [TrailingClosureHintInfo] {
    let visitor = TrailingClosureHintCollector(viewMode: .sourceAccurate)
    visitor.walk(tree)
    return visitor.hints
  }
}

/// Information about a trailing closure that may need an inlay hint.
struct TrailingClosureHintInfo {
  let trailingClosure: ClosureExprSyntax
  let functionCall: FunctionCallExprSyntax

  /// The opening brace of the trailing closure.
  var openingBrace: TokenSyntax {
    trailingClosure.leftBrace
  }
}

extension SwiftLanguageService {
  /// Generates inlay hints for trailing closures in the given range.
  ///
  /// Trailing closure hints display the parameter name immediately before the opening brace
  /// of a trailing closure, helping identify which parameter the closure satisfies.
  ///
  /// - Parameters:
  ///   - uri: The document URI.
  ///   - range: Optional range to filter hints. If nil, hints are generated for the entire document.
  ///   - options: Server configuration options.
  ///
  /// - Returns: An array of inlay hints for trailing closures.
  package func trailingClosureInlayHints(
    uri: DocumentURI,
    range: Range<Position>?,
    options: SourceKitLSPOptions
  ) async -> [InlayHint] {
    // Return early if feature is disabled
    guard options.inlayHintsOrDefault.trailingClosureLabelsOrDefault else {
      return []
    }

    do {
      let snapshot = try await self.latestSnapshot(for: uri)
      let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)

      let closureInfos = TrailingClosureHintCollector.collectTrailingClosures(in: syntaxTree)

      var hints: [InlayHint] = []

      for closureInfo in closureInfos {
        // Check if the closure is within the requested range
        if let range {
          let openingBracePosition = snapshot.position(
            of: closureInfo.openingBrace.endPositionBeforeTrailingTrivia
          )
          guard openingBracePosition >= range.lowerBound && openingBracePosition < range.upperBound else {
            continue
          }
        }

        // Try to get the parameter label from the function signature
        if let parameterLabel = await getTrailingClosureParameterLabel(
          for: closureInfo.functionCall,
          in: snapshot
        ) {
          let hintPosition = snapshot.position(of: closureInfo.openingBrace.endPositionBeforeTrailingTrivia)
          let label = ": \(parameterLabel)"

          let hint = InlayHint(
            position: hintPosition,
            label: .string(label),
            kind: .parameter,
            paddingLeft: false,
            paddingRight: false
          )
          hints.append(hint)
        }
      }

      return hints
    } catch {
      // If any error occurs during hint generation, return empty array
      return []
    }
  }

  /// Retrieves the parameter label for a trailing closure in a function call.
  ///
  /// This queries sourcekitd to determine the function's signature and identifies
  /// the parameter that the trailing closure satisfies.
  ///
  /// - Parameters:
  ///   - functionCall: The function call expression containing the trailing closure.
  ///   - snapshot: The document snapshot.
  ///
  /// - Returns: The parameter label if it can be determined, or nil if the information is unavailable.
  private func getTrailingClosureParameterLabel(
    for functionCall: FunctionCallExprSyntax,
    in snapshot: DocumentSnapshot
  ) async -> String? {
    let compileCommand = await self.compileCommand(for: snapshot.uri, fallbackAfterTimeout: false)

    // Query sourcekitd at the position of the function call to get information about the called function
    do {
      let calleePosition = snapshot.position(of: functionCall.calledExpression.endPositionBeforeTrailingTrivia)
      let calleeOffset = snapshot.utf8Offset(of: calleePosition)
      let skreq = sourcekitd.dictionary([
        keys.cancelOnSubsequentRequest: 0,
        keys.offset: calleeOffset,
        keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
        keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
        keys.compilerArgs: compileCommand?.compilerArgs as [any SKDRequestValue]?,
      ])

      let dict = try await send(sourcekitdRequest: \.cursorInfo, skreq, snapshot: snapshot)

      // Get the function signature and identify the trailing closure parameter
      // Try docFullAsXML first, then fallback to annotatedDecl
      var signature: String?
      if let xmlSig: String = dict[keys.docFullAsXML] {
        signature = xmlSig
      } else if let annotDecl: String = dict[keys.annotatedDecl] {
        signature = annotDecl
      }

      if let signature {
        return extractTrailingClosureParameterName(from: signature)
      }

      return nil
    } catch {
      // If sourcekitd query fails, we can't determine the parameter label
      return nil
    }
  }

  /// Extracts the trailing closure parameter name from a function signature.
  ///
  /// - Parameter signature: The function signature string (may be XML or plain text).
  /// - Returns: The parameter name if it can be determined.
  private func extractTrailingClosureParameterName(from signature: String) -> String? {
    // Common trailing closure parameter names in order of likelihood
    let commonNames = [
      "content",  // SwiftUI views
      "label",  // SwiftUI controls
      "body",  // View bodies
      "completion",  // Async operations
      "handler",  // Event handlers
      "onComplete",  // Callbacks
      "onSuccess",  // Async results
      "onFailure",  // Error handlers
    ]

    // Check for these common names in the signature
    for name in commonNames {
      // Look for parameter pattern: name: @escaping? (args) -> ReturnType
      let patterns = [
        "\\b\(name)\\s*:\\s*@escaping\\s*\\(",  // @escaping version
        "\\b\(name)\\s*:\\s*\\([^)]*\\)\\s*->",  // non-escaping version
        "\\b\(name)\\s*:\\s*@\\w+\\s*\\(\\)",  // simple closure
      ]

      for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
          let range = NSRange(signature.startIndex..., in: signature)
          if regex.firstMatch(in: signature, options: [], range: range) != nil {
            return name
          }
        }
      }
    }

    // Try to extract any closure parameter name using a more generic pattern
    // Look for: word: (something) -> or word: @escaping (something) ->
    let genericPattern = "\\b([a-zA-Z_]\\w*)\\s*:\\s*(?:@escaping\\s+)?\\([^)]*\\)\\s*->"
    if let regex = try? NSRegularExpression(pattern: genericPattern, options: []) {
      let range = NSRange(signature.startIndex..., in: signature)
      if let match = regex.firstMatch(in: signature, options: [], range: range),
        match.numberOfRanges > 1,
        let paramRange = Range(match.range(at: 1), in: signature)
      {
        let paramName = String(signature[paramRange])
        return paramName
      }
    }

    return nil
  }
}


func testHint() {
  let numbers = [1, 2]
  numbers.forEach { number in  
    print(number)
  }
}