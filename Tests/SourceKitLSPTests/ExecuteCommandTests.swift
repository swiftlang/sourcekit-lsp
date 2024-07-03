//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LSPTestSupport
import LanguageServerProtocol
import SKCore
import SKTestSupport
@_spi(Testing) import SourceKitLSP
import SwiftExtensions
import XCTest

final class ExecuteCommandTests: XCTestCase {
  func testLocationSemanticRefactoring() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func foo() {
        1️⃣"hello2️⃣"3️⃣
      }
      """,
      uri: uri
    )

    let args = SemanticRefactorCommand(
      title: "Localize String",
      actionString: "source.refactoring.kind.localize.string",
      positionRange: Range(positions["2️⃣"]),
      textDocument: TextDocumentIdentifier(uri)
    )

    let metadata = SourceKitLSPCommandMetadata(textDocument: TextDocumentIdentifier(uri))

    var command = args.asCommand()
    command.arguments?.append(metadata.encodeToLSPAny())

    let request = ExecuteCommandRequest(command: command.command, arguments: command.arguments)

    testClient.handleSingleRequest { (req: ApplyEditRequest) -> ApplyEditResponse in
      return ApplyEditResponse(applied: true, failureReason: nil)
    }

    let result = try await testClient.send(request)

    guard case .dictionary(let resultDict) = result else {
      XCTFail("Result is not a dictionary.")
      return
    }

    XCTAssertEqual(
      WorkspaceEdit(fromLSPDictionary: resultDict),
      WorkspaceEdit(changes: [
        uri: [
          TextEdit(
            range: Range(positions["1️⃣"]),
            newText: "NSLocalizedString("
          ),
          TextEdit(
            range: Range(positions["3️⃣"]),
            newText: ", comment: \"\")"
          ),
        ]
      ])
    )
  }

  func testRangeSemanticRefactoring() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      func foo() -> String {
        1️⃣var a = "hello"
        return a2️⃣
      }
      """,
      uri: uri
    )

    let args = SemanticRefactorCommand(
      title: "Extract Method",
      actionString: "source.refactoring.kind.extract.function",
      positionRange: positions["1️⃣"]..<positions["2️⃣"],
      textDocument: TextDocumentIdentifier(uri)
    )

    let metadata = SourceKitLSPCommandMetadata(textDocument: TextDocumentIdentifier(uri))

    var command = args.asCommand()
    command.arguments?.append(metadata.encodeToLSPAny())

    let request = ExecuteCommandRequest(command: command.command, arguments: command.arguments)

    testClient.handleSingleRequest { (req: ApplyEditRequest) -> ApplyEditResponse in
      return ApplyEditResponse(applied: true, failureReason: nil)
    }

    let result = try await testClient.send(request)

    guard case .dictionary(let resultDict) = result else {
      XCTFail("Result is not a dictionary.")
      return
    }

    XCTAssertEqual(
      WorkspaceEdit(fromLSPDictionary: resultDict),
      WorkspaceEdit(changes: [
        uri: [
          TextEdit(
            range: Range(Position(line: 0, utf16index: 0)),
            newText:
              """
              fileprivate func extractedFunc() -> String {
              var a = "hello"
                return a
              }


              """
          ),
          TextEdit(
            range: positions["1️⃣"]..<positions["2️⃣"],
            newText: "return extractedFunc()"
          ),
        ]
      ])
    )
  }

  func testFreestandingMacroExpansion() async throws {
    try await SkipUnless.canBuildMacroUsingSwiftSyntaxFromSourceKitLSPBuild()
    try await SkipUnless.swiftPMSupportsExperimentalPrepareForIndexing()

    let options = SourceKitLSPOptions.testDefault(experimentalFeatures: [.showMacroExpansions])

    let project = try await SwiftPMTestProject(
      files: [
        "MyMacros/MyMacros.swift": #"""
        import SwiftCompilerPlugin
        import SwiftSyntax
        import SwiftSyntaxBuilder
        import SwiftSyntaxMacros

        public struct StringifyMacro: ExpressionMacro {
          public static func expansion(
            of node: some FreestandingMacroExpansionSyntax,
            in context: some MacroExpansionContext
          ) -> ExprSyntax {
            guard let argument = node.argumentList.first?.expression else {
              fatalError("compiler bug: the macro does not have any arguments")
            }

            return "(\(argument), \(literal: argument.description))"
          }
        }

        @main
        struct MyMacroPlugin: CompilerPlugin {
          let providingMacros: [Macro.Type] = [
            StringifyMacro.self,
          ]
        }
        """#,
        "MyMacroClient/MyMacroClient.swift": """
        @freestanding(expression)
        public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "MyMacros", type: "StringifyMacro")

        func test() {
          1️⃣#2️⃣stringify3️⃣(1 + 2)
        }
        """,
      ],
      manifest: SwiftPMTestProject.macroPackageManifest,
      options: options
    )
    try await SwiftPMTestProject.build(at: project.scratchDirectory)

    let (uri, positions) = try project.openDocument("MyMacroClient.swift")

    let positionMarkersToBeTested = [
      (start: "1️⃣", end: "1️⃣"),
      (start: "2️⃣", end: "2️⃣"),
      (start: "1️⃣", end: "3️⃣"),
      (start: "2️⃣", end: "3️⃣"),
    ]

    for positionMarker in positionMarkersToBeTested {
      let args = ExpandMacroCommand(
        positionRange: positions[positionMarker.start]..<positions[positionMarker.end],
        textDocument: TextDocumentIdentifier(uri)
      )

      let metadata = SourceKitLSPCommandMetadata(textDocument: TextDocumentIdentifier(uri))

      var command = args.asCommand()
      command.arguments?.append(metadata.encodeToLSPAny())

      let request = ExecuteCommandRequest(command: command.command, arguments: command.arguments)

      let expectation = self.expectation(description: "Handle Show Document Request")
      let showDocumentRequestURI = ThreadSafeBox<DocumentURI?>(initialValue: nil)

      project.testClient.handleSingleRequest { (req: ShowDocumentRequest) in
        showDocumentRequestURI.value = req.uri
        expectation.fulfill()
        return ShowDocumentResponse(success: true)
      }

      let result = try await project.testClient.send(request)

      guard let resultArray: [RefactoringEdit] = Array(fromLSPArray: result ?? .null) else {
        XCTFail(
          "Result is not an array. Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
        )
        return
      }

      XCTAssertEqual(
        resultArray.count,
        1,
        "resultArray is empty. Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
      )
      XCTAssertEqual(
        resultArray.only?.newText,
        "(1 + 2, \"1 + 2\")",
        "Wrong macro expansion. Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
      )

      try await fulfillmentOfOrThrow([expectation])

      let url = try XCTUnwrap(
        showDocumentRequestURI.value?.fileURL,
        "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
      )

      let fileContents = try String(contentsOf: url, encoding: .utf8)

      XCTAssert(
        fileContents.contains("(1 + 2, \"1 + 2\")"),
        "File doesn't contain macro expansion. Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
      )

      XCTAssertEqual(
        url.lastPathComponent,
        "MyMacroClient_L4C2-L4C19.swift",
        "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
      )
    }
  }

  func testLSPCommandMetadataRetrieval() {
    var req = ExecuteCommandRequest(command: "", arguments: nil)
    XCTAssertNil(req.metadata)
    req.arguments = [1, 2, ""]
    XCTAssertNil(req.metadata)
    let url = URL(fileURLWithPath: "/a.swift")
    let textDocument = TextDocumentIdentifier(url)
    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)
    req.arguments = [metadata.encodeToLSPAny(), 1, 2, ""]
    XCTAssertNil(req.metadata)
    req.arguments = [1, 2, "", [metadata.encodeToLSPAny()]]
    XCTAssertNil(req.metadata)
    req.arguments = [1, 2, "", metadata.encodeToLSPAny()]
    XCTAssertEqual(req.metadata, metadata)
    req.arguments = [metadata.encodeToLSPAny()]
    XCTAssertEqual(req.metadata, metadata)
  }

  func testLSPCommandMetadataRemoval() {
    var req = ExecuteCommandRequest(command: "", arguments: nil)
    XCTAssertNil(req.argumentsWithoutSourceKitMetadata)
    req.arguments = [1, 2, ""]
    XCTAssertEqual(req.arguments, req.argumentsWithoutSourceKitMetadata)
    let url = URL(fileURLWithPath: "/a.swift")
    let textDocument = TextDocumentIdentifier(url)
    let metadata = SourceKitLSPCommandMetadata(textDocument: textDocument)
    req.arguments = [metadata.encodeToLSPAny(), 1, 2, ""]
    XCTAssertEqual(req.arguments, req.argumentsWithoutSourceKitMetadata)
    req.arguments = [1, 2, "", [metadata.encodeToLSPAny()]]
    XCTAssertEqual(req.arguments, req.argumentsWithoutSourceKitMetadata)
    req.arguments = [1, 2, "", metadata.encodeToLSPAny()]
    XCTAssertEqual([1, 2, ""], req.argumentsWithoutSourceKitMetadata)
  }
}
