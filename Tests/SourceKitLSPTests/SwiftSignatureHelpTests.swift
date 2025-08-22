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

import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
import XCTest

final class SwiftSignatureHelpTests: XCTestCase {
  func testSignatureHelpFunction() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      /// This is a test function
      /// - Parameters:
      ///   - a: The first parameter
      ///   - b: The second parameter
      /// - Returns: The result of the test
      func test(a: Int, b: String) -> Double { 0 }

      func main() {
        test(1️⃣)
      }
      """,
      uri: uri
    )

    let result = try await testClient.send(
      SignatureHelpRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )

    let signatureHelp = try XCTUnwrap(result)
    let signature = try XCTUnwrap(signatureHelp.signatures.only)

    XCTAssertEqual(signatureHelp.activeSignature, 0)
    XCTAssertEqual(signatureHelp.activeParameter, 0)
    XCTAssertEqual(signature.label, "test(a: Int, b: String) -> Double")
    XCTAssertEqual(
      signature.documentation,
      .markupContent(
        MarkupContent(
          kind: .markdown,
          value: """
            This is a test function
            - Parameters:
              - a: The first parameter
              - b: The second parameter
            - Returns: The result of the test
            """
        )
      )
    )
    XCTAssertEqual(
      signature.parameters,
      [
        ParameterInformation(label: .offsets(start: 5, end: 11)),
        ParameterInformation(label: .offsets(start: 13, end: 22)),
      ]
    )
  }

  func testSignatureHelpSubscript() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct Matrix {
        /// Returns the element at the given row and column
        /// - Parameters:
        ///   - row: The row index
        ///   - column: The column index
        /// - Returns: The element at the given row and column
        subscript(row: Int, column: Int) -> Int { 0 }
      }

      func main(matrix: Matrix) {
        matrix[1, 1️⃣]
      }
      """,
      uri: uri
    )

    let result = try await testClient.send(
      SignatureHelpRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )

    let signatureHelp = try XCTUnwrap(result)
    let signature = try XCTUnwrap(signatureHelp.signatures.only)

    XCTAssertEqual(signatureHelp.activeSignature, 0)
    XCTAssertEqual(signatureHelp.activeParameter, 1)
    XCTAssertEqual(signature.label, "subscript(row: Int, column: Int) -> Int")
    XCTAssertEqual(
      signature.documentation,
      .markupContent(
        MarkupContent(
          kind: .markdown,
          value: """
            Returns the element at the given row and column
            - Parameters:
              - row: The row index
              - column: The column index
            - Returns: The element at the given row and column
            """
        )
      )
    )
    XCTAssertEqual(
      signature.parameters,
      [
        ParameterInformation(label: .offsets(start: 10, end: 18)),
        ParameterInformation(label: .offsets(start: 20, end: 31)),
      ]
    )
  }

  func testSignatureHelpInitializer() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct Matrix {
        /// Initializes a matrix with 0 elements in each row and column
        ///
        /// - Precondition: `rows` and `columns` must be positive
        init(rows: Int, columns: Int) { }
      }

      func main() {
        let matrix = Matrix(rows: 3, 1️⃣)
      }
      """,
      uri: uri
    )

    let result = try await testClient.send(
      SignatureHelpRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )

    let signatureHelp = try XCTUnwrap(result)
    let signature = try XCTUnwrap(signatureHelp.signatures.only)

    XCTAssertEqual(signatureHelp.activeSignature, 0)
    XCTAssertEqual(signatureHelp.activeParameter, 1)
    XCTAssertEqual(signature.label, "init(rows: Int, columns: Int)")
    XCTAssertEqual(
      signature.documentation,
      .markupContent(
        MarkupContent(
          kind: .markdown,
          value: """
            Initializes a matrix with 0 elements in each row and column

            - Precondition: `rows` and `columns` must be positive
            """
        )
      )
    )
    XCTAssertEqual(
      signature.parameters,
      [
        ParameterInformation(label: .offsets(start: 5, end: 14)),
        ParameterInformation(label: .offsets(start: 16, end: 28)),
      ]
    )
  }

  func testSignatureHelpWithNoParameters() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      /// This is a test function
      func test() -> Double { 0 }

      func main() {
        test(1️⃣)
      }
      """,
      uri: uri
    )

    let result = try await testClient.send(
      SignatureHelpRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )

    let signatureHelp = try XCTUnwrap(result)
    let signature = try XCTUnwrap(signatureHelp.signatures.only)

    XCTAssertEqual(signatureHelp.activeSignature, 0)
    XCTAssertNil(signatureHelp.activeParameter)
    XCTAssertEqual(signature.label, "test() -> Double")
    XCTAssertEqual(
      signature.documentation,
      .markupContent(
        MarkupContent(kind: .markdown, value: "This is a test function")
      )
    )
    XCTAssertEqual(signature.parameters?.isEmpty, true)
  }

  func testSignatureHelpNoSignatures() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func main() {
        test(1️⃣)
      }
      """,
      uri: uri
    )

    let result = try await testClient.send(
      SignatureHelpRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )

    XCTAssertNil(result)
  }

  func testSignatureHelpAdjustToStartOfArgument() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct Adder {
        func add(first: Double!, second: Float, third: Int) -> Double { 0 }
        func clone() -> Adder { self }
      }

      func main(adder: Adder) {
        adder.add(1️⃣fir2️⃣st: 13️⃣, second: 2 + 4️⃣Float.pi, 5️⃣third: 3)
        adder.add(first: adder.add(first: 1, second: 6️⃣))
        adder.clone().add(7️⃣)
      }
      """,
      uri: uri
    )

    func getSignature(marker: String, line: UInt = #line) async throws -> SignatureInformation {
      let result = try await testClient.send(
        SignatureHelpRequest(
          textDocument: TextDocumentIdentifier(uri),
          position: positions[marker]
        )
      )

      let signatureHelp = try XCTUnwrap(result)
      let signature = try XCTUnwrap(signatureHelp.signatures.only)

      XCTAssertEqual(signature.label, "add(first: Double!, second: Float, third: Int) -> Double", line: line)
      XCTAssertNil(signature.documentation)
      XCTAssertEqual(
        signature.parameters,
        [
          ParameterInformation(label: .offsets(start: 4, end: 18)),
          ParameterInformation(label: .offsets(start: 20, end: 33)),
          ParameterInformation(label: .offsets(start: 35, end: 45)),
        ]
      )

      return signature
    }

    let firstPosition = try await getSignature(marker: "1️⃣")
    XCTAssertEqual(firstPosition.activeParameter, 0)

    let secondPosition = try await getSignature(marker: "2️⃣")
    XCTAssertEqual(secondPosition.activeParameter, 0)

    let thirdPosition = try await getSignature(marker: "3️⃣")
    XCTAssertEqual(thirdPosition.activeParameter, 0)

    let fourthPosition = try await getSignature(marker: "4️⃣")
    XCTAssertEqual(fourthPosition.activeParameter, 1)

    let fifthPosition = try await getSignature(marker: "5️⃣")
    XCTAssertEqual(fifthPosition.activeParameter, 2)

    let sixthPosition = try await getSignature(marker: "6️⃣")
    XCTAssertEqual(sixthPosition.activeParameter, 1)

    let seventhPosition = try await getSignature(marker: "7️⃣")
    XCTAssertEqual(seventhPosition.activeParameter, 0)
  }

  func testSignatureHelpMultipleOverloads() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct Adder {
        func add(_ x: Int, to y: Int) -> Int { 0 }

        /// Adds one to an integer
        func add(oneTo x: inout Int) { }
      }

      func test(adder: Adder) {
        adder.add(1️⃣)
      }
      """,
      uri: uri
    )

    let result = try await testClient.send(
      SignatureHelpRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )

    let signatureHelp = try XCTUnwrap(result)
    XCTAssertEqual(signatureHelp.activeSignature, 0)
    XCTAssertEqual(signatureHelp.activeParameter, 0)
    XCTAssertEqual(signatureHelp.signatures.count, 2)

    let firstSignature = try XCTUnwrap(signatureHelp.signatures[0])
    XCTAssertEqual(firstSignature.label, "add(_ x: Int, to: Int) -> Int")
    XCTAssertEqual(firstSignature.activeParameter, 0)
    XCTAssertNil(firstSignature.documentation)
    XCTAssertEqual(
      firstSignature.parameters,
      [
        ParameterInformation(label: .offsets(start: 4, end: 12)),
        ParameterInformation(label: .offsets(start: 14, end: 21)),
      ]
    )

    let secondSignature = try XCTUnwrap(signatureHelp.signatures[1])
    XCTAssertEqual(secondSignature.label, "add(oneTo: inout Int)")
    XCTAssertEqual(secondSignature.activeParameter, 0)
    XCTAssertEqual(
      secondSignature.parameters,
      [ParameterInformation(label: .offsets(start: 4, end: 20))]
    )
    XCTAssertEqual(
      secondSignature.documentation,
      .markupContent(MarkupContent(kind: .markdown, value: "Adds one to an integer"))
    )
  }

  func testSignatureHelpSwiftPMProject() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "utils.swift": """
        /// A utility function that combines values
        /// - Parameters:
        ///   - first: The first value
        ///   - second: The second value
        /// - Returns: The combined result
        func combine(first: String, second: Int) -> String {
          return "\\(first)-\\(second)"
        }
        """,
        "main.swift": """
        func test() {
          combine(1️⃣)
        }
        """,
      ]
    )
    let (uri, positions) = try project.openDocument("main.swift")

    let result = try await project.testClient.send(
      SignatureHelpRequest(
        textDocument: TextDocumentIdentifier(uri),
        position: positions["1️⃣"]
      )
    )

    let signatureHelp = try XCTUnwrap(result)
    let signature = try XCTUnwrap(signatureHelp.signatures.only)

    XCTAssertEqual(signature.label, "combine(first: String, second: Int) -> String")
    XCTAssertEqual(signatureHelp.activeSignature, 0)
    XCTAssertEqual(signatureHelp.activeParameter, 0)
    XCTAssertEqual(
      signature.documentation,
      .markupContent(
        MarkupContent(
          kind: .markdown,
          value: """
            A utility function that combines values
            - Parameters:
              - first: The first value
              - second: The second value
            - Returns: The combined result
            """
        )
      )
    )
    XCTAssertEqual(
      signature.parameters,
      [
        ParameterInformation(label: .offsets(start: 8, end: 21)),
        ParameterInformation(label: .offsets(start: 23, end: 34)),
      ]
    )
  }
}
