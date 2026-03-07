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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SourceKitLSP
import SwiftSyntax

/// Scans a source file for `XCTestCase` classes and test methods.
///
/// The syntax visitor scans from class and extension declarations that could be `XCTestCase` classes or extensions
/// thereof. It then calls into `findTestMethods` to find the actual test methods.
final class SyntacticSwiftXCTestScanner: SyntaxVisitor {
  /// The document snapshot of the syntax tree that is being walked.
  private var snapshot: DocumentSnapshot

  /// The workspace symbols representing the found `XCTestCase` subclasses and test methods.
  private var result: [AnnotatedTestItem] = []

  private init(snapshot: DocumentSnapshot) {
    self.snapshot = snapshot
    super.init(viewMode: .fixedUp)
  }

  package static func findTestSymbols(
    in snapshot: DocumentSnapshot,
    syntaxTreeManager: SyntaxTreeManager
  ) async -> [AnnotatedTestItem] {
    guard snapshot.text.contains("XCTestCase") || snapshot.text.contains("test") else {
      // If the file contains tests that can be discovered syntactically, it needs to have a class inheriting from
      // `XCTestCase` or a function starting with `test`.
      // This is intended to filter out files that obviously do not contain tests.
      return []
    }
    let syntaxTree = await syntaxTreeManager.syntaxTree(for: snapshot)
    let visitor = SyntacticSwiftXCTestScanner(snapshot: snapshot)
    visitor.walk(syntaxTree)
    return visitor.result
  }

  private func findTestMethods(in members: MemberBlockItemListSyntax, containerName: String) -> [TestItem] {
    return members.compactMap { (member) -> TestItem? in
      guard let function = member.decl.as(FunctionDeclSyntax.self) else {
        return nil
      }
      guard function.name.text.starts(with: "test") else {
        return nil
      }
      guard function.modifiers.map(\.name.tokenKind).allSatisfy({ $0 != .keyword(.static) && $0 != .keyword(.class) })
      else {
        // Test methods can't be static.
        return nil
      }
      guard function.signature.returnClause == nil, function.signature.parameterClause.parameters.isEmpty else {
        // Test methods can't have a return type or have parameters.
        // Technically we are also filtering out functions that have an explicit `Void` return type here but such
        // declarations are probably less common than helper functions that start with `test` and have a return type.
        return nil
      }
      let range = snapshot.absolutePositionRange(
        of: function.positionAfterSkippingLeadingTrivia..<function.endPositionBeforeTrailingTrivia
      )

      return TestItem(
        id: "\(containerName)/\(function.name.text)()",
        label: "\(function.name.text)()",
        disabled: false,
        style: TestStyle.xcTest,
        location: Location(uri: snapshot.uri, range: range),
        children: [],
        tags: []
      )
    }
  }

  func handleClassOrExtension(
    _ node: some DeclGroupSyntax,
    name: String,
    isKnownXCTestCaseSubclass: Bool
  ) -> SyntaxVisitorContinueKind {
    let testMethods = findTestMethods(in: node.memberBlock.members, containerName: name)

    guard !testMethods.isEmpty || isKnownXCTestCaseSubclass else {
      // Don't report a test class if it doesn't contain any test methods.
      return .visitChildren
    }

    let range = snapshot.absolutePositionRange(
      of: node.positionAfterSkippingLeadingTrivia..<node.endPositionBeforeTrailingTrivia
    )
    let testItem = AnnotatedTestItem(
      testItem: TestItem(
        id: name,
        label: name,
        disabled: false,
        style: TestStyle.xcTest,
        location: Location(uri: snapshot.uri, range: range),
        children: testMethods,
        tags: []
      ),
      isExtension: node.is(ExtensionDeclSyntax.self)
    )
    result.append(testItem)
    return .visitChildren
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    guard let inheritedTypes = node.inheritanceClause?.inheritedTypes, let superclass = inheritedTypes.first else {
      // The class has no superclass and thus can't inherit from XCTestCase.
      // Continue scanning its children in case it has a nested subclass that inherits from XCTestCase.
      return .visitChildren
    }
    let superclassName = superclass.type.as(IdentifierTypeSyntax.self)?.name.text
    if superclassName == "NSObject" {
      // We know that the class can't be an subclass of `XCTestCase` so don't visit it.
      // We can't explicitly check for the `XCTestCase` superclass because the class might inherit from a class that in
      // turn inherits from `XCTestCase`. Resolving that inheritance hierarchy would be semantic.
      return .visitChildren
    }
    return handleClassOrExtension(node, name: node.name.text, isKnownXCTestCaseSubclass: superclassName == "XCTestCase")
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    handleClassOrExtension(node, name: node.extendedType.trimmedDescription, isKnownXCTestCaseSubclass: false)
  }
}
