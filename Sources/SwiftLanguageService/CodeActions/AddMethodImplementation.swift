//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SourceKitLSP
import SwiftParser
import SwiftSyntax

/// Provides code actions to add method implementations for incomplete implementations.
public struct AddMethodImplementation {
  
  /// Creates code actions to add missing method implementations.
  /// - Parameters:
  ///   - diagnostics: The diagnostics that triggered this code action request
  ///   - snapshot: The document snapshot
  ///   - workspace: The workspace containing the document
  /// - Returns: Array of code actions to add method implementations
  static func codeActions(
    diagnostics: [Diagnostic],
    snapshot: DocumentSnapshot,
    workspace: Workspace
  ) -> [CodeAction] {
    // Filter for incomplete implementation diagnostics
    let incompleteDiagnostics = diagnostics.filter { diagnostic in
      let message = diagnostic.message
      return message.localizedCaseInsensitiveContains("incomplete implementation") ||
      message.localizedCaseInsensitiveContains("does not conform to protocol") ||
      message.localizedCaseInsensitiveContains("does not conform to") ||
      message.localizedCaseInsensitiveContains("missing implementation")
    }
    
    guard !incompleteDiagnostics.isEmpty else {
      return []
    }
    
    return generateAddMethodActions(
      snapshot: snapshot,
      workspace: workspace
    )
  }
  
  private static func generateAddMethodActions(
    snapshot: DocumentSnapshot,
    workspace: Workspace
  ) -> [CodeAction] {
    let text = snapshot.text
    guard !text.isEmpty else {
      return []
    }
    
    // Detect file language
    let fileExtension = URL(fileURLWithPath: snapshot.uri.pseudoPath).pathExtension
    let isObjectiveC = fileExtension == "m" || fileExtension == "mm" || fileExtension == "h"
    
    if isObjectiveC {
      return generateObjectiveCMethodActions(snapshot: snapshot, workspace: workspace)
    } else {
      // Swift implementation
      return generateSwiftMethodActions(snapshot: snapshot, workspace: workspace)
    }
  }
  
  private static func generateObjectiveCMethodActions(
    snapshot: DocumentSnapshot,
    workspace: Workspace
  ) -> [CodeAction] {
    let text = snapshot.text
    
    // For Objective-C, look for incomplete implementation patterns
    let missingMethods = findObjectiveCMissingMethods(in: text)
    guard !missingMethods.isEmpty else {
      return []
    }
    
    return missingMethods.map { method in
      let insertPosition = findObjectiveCInsertionPosition(in: text)
      let edit = TextEdit(
        range: insertPosition..<insertPosition,
        newText: generateObjectiveCMethodImplementation(method: method)
      )
      
      return CodeAction(
        title: "Add implementation for '\(method.selector)'",
        kind: .quickFix,
        edit: WorkspaceEdit(changes: [snapshot.uri: [edit]])
      )
    }
  }
  
  private static func generateSwiftMethodActions(
    snapshot: DocumentSnapshot,
    workspace: Workspace
  ) -> [CodeAction] {
    let text = snapshot.text
    
    // Parse the syntax tree to find incomplete implementations
    let parseResult = Parser.parse(source: text)
    let syntaxTree = parseResult
    guard !syntaxTree.description.isEmpty else {
      return []
    }
    
    let missingMethods = findSwiftMissingMethods(in: syntaxTree, sourceText: text)
    guard !missingMethods.isEmpty else {
      return []
    }
    
    // Find a good insertion point (end of class/struct)
    guard let insertPosition = findSwiftInsertionPosition(in: syntaxTree, sourceText: text) else {
      return []
    }
    
    return missingMethods.map { method in
      let edit = TextEdit(
        range: insertPosition..<insertPosition,
        newText: generateSwiftMethodImplementation(method: method)
      )
      
      return CodeAction(
        title: "Add implementation for '\(method.name)'",
        kind: .quickFix,
        edit: WorkspaceEdit(changes: [snapshot.uri: [edit]])
      )
    }
  }
  
  private struct MissingMethod {
    let name: String
    let returnType: String
    let parameters: [(name: String, type: String)]
    let isStatic: Bool
    let accessLevel: String
  }
  
  private struct ObjectiveCMissingMethod {
    let selector: String
    let returnType: String
    let parameters: [(name: String, type: String)]
    let isClassMethod: Bool
    let className: String
  }
  
  private static func findSwiftMissingMethods(
    in syntaxTree: SourceFileSyntax,
    sourceText: String
  ) -> [MissingMethod] {
    let missingMethods: [MissingMethod] = []
    
    // Visit the syntax tree to find protocol conformance issues
    class IncompleteImplementationVisitor: SyntaxVisitor {
      let sourceText: String
      var missingMethods: [MissingMethod] = []
      
      init(sourceText: String) {
        self.sourceText = sourceText
        super.init(viewMode: .sourceAccurate)
      }
      
      override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkForMissingImplementations(in: node, type: "class")
        return .visitChildren
      }
      
      override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkForMissingImplementations(in: node, type: "struct")
        return .visitChildren
      }
      
      private func checkForMissingImplementations<T: DeclSyntaxProtocol>(in node: T, type: String) {
        // Look for diagnostics or comments indicating incomplete implementation
        // This is a simplified approach - in a real implementation we'd want to
        // use the compiler's diagnostic information more directly
        // TODO: This is a placeholder implementation
      }
    }
    
    let visitor = IncompleteImplementationVisitor(sourceText: sourceText)
    visitor.walk(syntaxTree)
    
    // For now, return empty array since we need more sophisticated analysis
    // This would be enhanced with proper diagnostic correlation
    return missingMethods
  }
  
  private static func findObjectiveCMissingMethods(in text: String) -> [ObjectiveCMissingMethod] {
    var missingMethods: [ObjectiveCMissingMethod] = []
    
    // Simple pattern matching for incomplete implementation warnings
    // In a real implementation, this would be more sophisticated
    let patterns = [
      // Match patterns like "Method 'methodName:' in class 'ClassName' not found"
      "Method '([^']+)' in class '([^']+)' not found",
      // Match patterns like "Instance method 'methodName:' not implemented"
      "Instance method '([^']+)' not implemented",
      // Match patterns like "Class method 'methodName:' not implemented"
      "Class method '([^']+)' not implemented"
    ]
    
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else {
        continue
      }
      
      let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
      
      for match in matches {
        if match.numberOfRanges >= 3 {
          let methodName = (text as NSString).substring(with: match.range(at: 1))
          let className = (text as NSString).substring(with: match.range(at: 2))
          
          // Create a basic missing method structure
          let missingMethod = ObjectiveCMissingMethod(
            selector: methodName,
            returnType: "void",
            parameters: [],
            isClassMethod: methodName.hasPrefix("+"),
            className: className
          )
          missingMethods.append(missingMethod)
        }
      }
    }
    
    return missingMethods
  }
  
  private static func findSwiftInsertionPosition(
    in syntaxTree: SourceFileSyntax,
    sourceText: String
  ) -> Position? {
    // Find the last token in the main type declaration
    if let lastToken = syntaxTree.lastToken(viewMode: .sourceAccurate) {
      _ = lastToken.positionAfterSkippingLeadingTrivia
      // Return a position at the end of the file
      return Position(line: 999999, utf16index: 0)
    }
    
    return Position(line: 0, utf16index: 0)
  }
  
  private static func findObjectiveCInsertionPosition(in text: String) -> Position {
    // Find the end of the last @implementation block or return beginning of file
    if let range = text.range(of: "@end", options: .backwards) {
      let lineStart = range.lowerBound
      let lineNumber = text[..<lineStart].components(separatedBy: .newlines).count - 1
      return Position(line: lineNumber, utf16index: 0)
    }
    
    return Position(line: 0, utf16index: 0)
  }
  
  private static func generateSwiftMethodImplementation(method: MissingMethod) -> String {
    let accessPrefix = method.accessLevel.isEmpty ? "" : "\(method.accessLevel) "
    let staticPrefix = method.isStatic ? "static " : ""
    let parameters = method.parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
    
    return """

    \(accessPrefix)\(staticPrefix)func \(method.name)(\(parameters)) -> \(method.returnType) {
        // TODO: implement
        fatalError("Not implemented")
    }

    """
  }
  
  private static func generateObjectiveCMethodImplementation(method: ObjectiveCMissingMethod) -> String {
    let methodPrefix = method.isClassMethod ? "+" : "-"
    let parameters = method.parameters.map { "\($0.name):(\($0.type))\($0.name)" }.joined(separator: " ")
    
    return """

    \(methodPrefix) (\(method.returnType))\(parameters) {
        // TODO: implement
        NSAssert(NO, @"Method not yet implemented");
    }

    """
  }
}

// Helper extension to check if a string contains a substring (case-insensitive)
extension String {
  func localizedContains(_ searchString: String) -> Bool {
    return localizedCaseInsensitiveContains(searchString)
  }
}
