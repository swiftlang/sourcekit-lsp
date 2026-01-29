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
            of: closureInfo.openingBrace.positionAfterSkippingLeadingTrivia
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
          let hintPosition = snapshot.position(of: closureInfo.openingBrace.positionAfterSkippingLeadingTrivia)
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
  /// Uses sourcekitd's signatureHelp to get structured parameter information,
  /// then determines which parameter the trailing closure satisfies based on
  /// the number of labeled arguments.
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

    // Use signatureHelp request at the position just before the trailing closure
    // This gives us structured parameter information
    do {
      // Position the query at the opening parenthesis or just before the trailing closure
      let queryPosition: AbsolutePosition
      if let leftParen = functionCall.leftParen {
        queryPosition = leftParen.endPosition
      } else {
        // For calls without parentheses, use the end of the called expression
        queryPosition = functionCall.calledExpression.endPosition
      }

      let position = snapshot.position(of: queryPosition)
      let offset = snapshot.utf8Offset(of: position)

      let skreq = sourcekitd.dictionary([
        keys.offset: offset,
        keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
        keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
        keys.compilerArgs: compileCommand?.compilerArgs as [any SKDRequestValue]?,
      ])

      let dict = try await send(sourcekitdRequest: \.signatureHelp, skreq, snapshot: snapshot)

      // Extract parameter information from the signature help response
      guard let signatures: SKDResponseArray = dict[keys.signatures],
        signatures.count > 0,
        let firstSignature = signatures[0] as? SKDResponseDictionary,
        let parameters: SKDResponseArray = firstSignature[keys.parameters]
      else {
        return nil
      }

      // Count the number of labeled arguments provided before the trailing closure
      let labeledArgsCount = functionCall.arguments.count

      // The trailing closure satisfies the parameter at index = labeledArgsCount
      guard labeledArgsCount < parameters.count else {
        return nil
      }

      // Get the parameter at the trailing closure's position
      guard let parameter = parameters[labeledArgsCount] as? SKDResponseDictionary,
        let paramName: String = parameter[keys.name]
      else {
        return nil
      }

      // Extract just the external parameter name (before any colon)
      // signatureHelp returns full parameter syntax like "content: () -> Content"
      if let colonIndex = paramName.firstIndex(of: ":") {
        let extracted = String(paramName[..<colonIndex])
        return extracted.trimmingCharacters(in: CharacterSet.whitespaces)
      }

      return paramName.trimmingCharacters(in: CharacterSet.whitespaces)
    } catch {
      return nil
    }
  }
}
