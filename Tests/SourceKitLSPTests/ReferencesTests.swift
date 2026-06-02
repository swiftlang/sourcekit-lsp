//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import XCTest

/// Tests that test the overall state of the SourceKit-LSP server, that's not really specific to any language
final class ReferencesTests: SourceKitLSPTestCase {
  func testReferencesInMacro() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      import Observation

      @available(macOS 14.0, *)
      1️⃣@Observable
      class 2️⃣Foo {
        var x: Int = 2
      }
      """
    )

    let response = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["2️⃣"],
        context: ReferencesContext(includeDeclaration: true)
      )
    )
    XCTAssertEqual(
      response,
      [
        Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
        Location(uri: project.fileURI, range: Range(project.positions["2️⃣"])),
      ]
    )
  }

  func testReferencesWithoutDeclaration() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func 1️⃣foo() {}

      func bar() {
        2️⃣foo()
        3️⃣foo()
      }
      """
    )
    let response = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"],
        context: ReferencesContext(includeDeclaration: false)
      )
    )
    XCTAssertEqual(
      response,
      [
        Location(uri: project.fileURI, range: Range(project.positions["2️⃣"])),
        Location(uri: project.fileURI, range: Range(project.positions["3️⃣"])),
      ]
    )
  }

  func testLocalVariableReferences() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func testReferences() {
        let 1️⃣myLocalVariable = "Hello"
        print(2️⃣myLocalVariable)
        
        if true {
          let 3️⃣myLocalVariable = "Shadowed"
          print(4️⃣myLocalVariable)
        }
        
        let stringLength = 5️⃣myLocalVariable.count
      }
      """
    )

    let outerRefs = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"],
        context: ReferencesContext(includeDeclaration: true)
      )
    )

    _ = outerRefs.map { $0.range.lowerBound }
    XCTAssertEqual(
      Set(outerRefs.map(\.range.lowerBound)),
      [
        project.positions["1️⃣"],
        project.positions["2️⃣"],
        project.positions["5️⃣"],
      ]
    )

    let innerRefs = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["4️⃣"],
        context: ReferencesContext(includeDeclaration: true)
      )
    )

    XCTAssertEqual(
      Set(innerRefs.map(\.range.lowerBound)),
      Set([
        project.positions["3️⃣"],
        project.positions["4️⃣"],
      ])
    )

    let outerRefsWithoutDecl = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"],
        context: ReferencesContext(includeDeclaration: false)
      )
    )

    XCTAssertEqual(
      Set(outerRefsWithoutDecl.map(\.range.lowerBound)),
      [
        project.positions["2️⃣"],
        project.positions["5️⃣"],
      ]
    )
  }

  func testSimpleLocalVariableReferences() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func foo() {
        let 1️⃣x = 1
        print(2️⃣x)
        print(3️⃣x)
      }
      """
    )

    let refs = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["2️⃣"],
        context: ReferencesContext(includeDeclaration: true)
      )
    )

    XCTAssertEqual(
      Set(refs.map(\.range.lowerBound)),
      [
        project.positions["1️⃣"],
        project.positions["2️⃣"],
        project.positions["3️⃣"],
      ]
    )
  }

  func testLocalVariableReferencesWithoutDeclaration() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func foo() {
        let 1️⃣x = 1
        print(2️⃣x)
        print(3️⃣x)
      }
      """
    )

    let response = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["2️⃣"],
        context: ReferencesContext(includeDeclaration: false)
      )
    )

    XCTAssertEqual(
      Set(response.map(\.range.lowerBound)),
      [
        project.positions["2️⃣"],
        project.positions["3️⃣"],
      ]
    )
  }

  func testParameterReferences() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      func foo(1️⃣x: Int) {
        print(2️⃣x)
        print(3️⃣x)
      }
      """
    )

    let responseWithoutDecl = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"],
        context: ReferencesContext(includeDeclaration: false)
      )
    )

    XCTAssertEqual(
      Set(responseWithoutDecl.map(\.range.lowerBound)),
      [
        project.positions["2️⃣"],
        project.positions["3️⃣"],
      ]
    )

    let responseWithDecl = try await project.testClient.send(
      ReferencesRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"],
        context: ReferencesContext(includeDeclaration: true)
      )
    )

    XCTAssertEqual(
      Set(responseWithDecl.map(\.range.lowerBound)),
      [
        project.positions["1️⃣"],
        project.positions["2️⃣"],
        project.positions["3️⃣"],
      ]
    )
  }
}
