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

import LanguageServerProtocol
import SKOptions
import SKTestSupport
@_spi(Testing) import SourceKitLSP
import SwiftExtensions
import XCTest

final class ExpandMacroTests: XCTestCase {
  func testFreestandingMacroExpansion() async throws {
    try await SkipUnless.canBuildMacroUsingSwiftSyntaxFromSourceKitLSPBuild()
    try await SkipUnless.swiftPMSupportsExperimentalPrepareForIndexing()

    let files: [RelativeFileLocation: String] = [
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
          guard let argument = node.arguments.first?.expression else {
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
    ]

    for (getReferenceDocument, peekDocuments) in cartesianProduct([true], [true]) {
      let project = try await SwiftPMTestProject(
        files: files,
        manifest: SwiftPMTestProject.macroPackageManifest,
        capabilities: ClientCapabilities(experimental: [
          "workspace/peekDocuments": .bool(peekDocuments),
          "workspace/getReferenceDocument": .bool(getReferenceDocument),
        ]),
        options: SourceKitLSPOptions.testDefault(),
        enableBackgroundIndexing: true
      )

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

        if peekDocuments && getReferenceDocument {
          let expectation = self.expectation(description: "Handle Peek Documents Request")
          let peekDocumentsRequestURIs = ThreadSafeBox<[DocumentURI]?>(initialValue: nil)

          project.testClient.handleSingleRequest { (req: PeekDocumentsRequest) in
            peekDocumentsRequestURIs.value = req.locations
            expectation.fulfill()
            return PeekDocumentsResponse(success: true)
          }

          _ = try await project.testClient.send(request)

          try await fulfillmentOfOrThrow([expectation])

          let uris = try XCTUnwrap(
            peekDocumentsRequestURIs.value,
            "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )

          var filesContents = [String]()
          for uri in uris {
            let result = try await project.testClient.send(GetReferenceDocumentRequest(uri: uri))

            filesContents.append(result.content)
          }

          XCTAssertEqual(
            filesContents.only,
            "(1 + 2, \"1 + 2\")",
            "File doesn't contain macro expansion. Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )

          let urls = uris.map { $0.arbitrarySchemeURL }

          XCTAssertEqual(
            urls.only?.lastPathComponent,
            "L5C3-L5C20.swift",
            "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )
        } else {
          let expectation = self.expectation(description: "Handle Show Document Request")
          let showDocumentRequestURI = ThreadSafeBox<DocumentURI?>(initialValue: nil)

          project.testClient.handleSingleRequest { (req: ShowDocumentRequest) in
            showDocumentRequestURI.value = req.uri
            expectation.fulfill()
            return ShowDocumentResponse(success: true)
          }

          _ = try await project.testClient.send(request)

          try await fulfillmentOfOrThrow([expectation])

          let url = try XCTUnwrap(
            showDocumentRequestURI.value?.fileURL,
            "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )

          let fileContents = try String(contentsOf: url, encoding: .utf8)

          XCTAssertEqual(
            fileContents,
            """
            // MyMacroClient.swift @ 5:3 - 5:20
            (1 + 2, \"1 + 2\")

            """,
            "File doesn't contain macro expansion. Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )

          XCTAssertEqual(
            url.lastPathComponent,
            "MyMacroClient.swift",
            "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )
        }
      }
    }
  }

  func testAttachedMacroExpansion() async throws {
    try await SkipUnless.canBuildMacroUsingSwiftSyntaxFromSourceKitLSPBuild()
    try await SkipUnless.swiftPMSupportsExperimentalPrepareForIndexing()

    let files: [RelativeFileLocation: String] = [
      "MyMacros/MyMacros.swift": #"""
      import SwiftCompilerPlugin
      import SwiftSyntax
      import SwiftSyntaxBuilder
      import SwiftSyntaxMacros

      public struct DictionaryStorageMacro {}

      extension DictionaryStorageMacro: MemberMacro {
        public static func expansion(
          of node: AttributeSyntax,
          providingMembersOf declaration: some DeclGroupSyntax,
          in context: some MacroExpansionContext
        ) throws -> [DeclSyntax] {
          return ["\n  var _storage: [String: Any] = [:]"]
        }
      }

      extension DictionaryStorageMacro: MemberAttributeMacro {
        public static func expansion(
          of node: AttributeSyntax,
          attachedTo declaration: some DeclGroupSyntax,
          providingAttributesFor member: some DeclSyntaxProtocol,
          in context: some MacroExpansionContext
        ) throws -> [AttributeSyntax] {
          return [
            AttributeSyntax(
              leadingTrivia: [.newlines(1), .spaces(2)],
              attributeName: IdentifierTypeSyntax(
                name: .identifier("DictionaryStorageProperty")
              )
            )
          ]
        }
      }

      @main
      struct MyMacroPlugin: CompilerPlugin {
        let providingMacros: [Macro.Type] = [
          DictionaryStorageMacro.self
        ]
      }
      """#,
      "MyMacroClient/MyMacroClient.swift": #"""
      @attached(memberAttribute)
      @attached(member, names: named(_storage))
      public macro DictionaryStorage() = #externalMacro(module: "MyMacros", type: "DictionaryStorageMacro")

      1️⃣@2️⃣DictionaryStorage3️⃣
      struct Point {
        var x: Int = 1
        var y: Int = 2
      }
      """#,
    ]

    for (getReferenceDocument, peekDocuments) in cartesianProduct([true, false], [true, false]) {
      let project = try await SwiftPMTestProject(
        files: files,
        manifest: SwiftPMTestProject.macroPackageManifest,
        capabilities: ClientCapabilities(experimental: [
          "workspace/peekDocuments": .bool(peekDocuments),
          "workspace/getReferenceDocument": .bool(getReferenceDocument),
        ]),
        options: SourceKitLSPOptions.testDefault(),
        enableBackgroundIndexing: true
      )

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

        if peekDocuments && getReferenceDocument {
          let expectation = self.expectation(description: "Handle Peek Documents Request")

          let peekDocumentsRequestURIs = ThreadSafeBox<[DocumentURI]?>(initialValue: nil)

          project.testClient.handleSingleRequest { (req: PeekDocumentsRequest) in
            peekDocumentsRequestURIs.value = req.locations
            expectation.fulfill()
            return PeekDocumentsResponse(success: true)
          }

          _ = try await project.testClient.send(request)

          try await fulfillmentOfOrThrow([expectation])

          let uris = try XCTUnwrap(
            peekDocumentsRequestURIs.value,
            "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )

          var filesContents = [String]()
          for uri in uris {
            let result = try await project.testClient.send(GetReferenceDocumentRequest(uri: uri))

            filesContents.append(result.content)
          }

          XCTAssertEqual(
            filesContents,
            [
              "@DictionaryStorageProperty",
              "@DictionaryStorageProperty",
              "var _storage: [String: Any] = [:]",
            ],
            "Files doesn't contain correct macro expansion. Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )

          let urls = uris.map { $0.arbitrarySchemeURL }

          XCTAssertEqual(
            urls.map { $0.lastPathComponent },
            [
              "L7C3-L7C3.swift",
              "L8C3-L8C3.swift",
              "L9C1-L9C1.swift",
            ],
            "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )
        } else {
          let expectation = self.expectation(description: "Handle Show Document Request")
          let showDocumentRequestURI = ThreadSafeBox<DocumentURI?>(initialValue: nil)

          project.testClient.handleSingleRequest { (req: ShowDocumentRequest) in
            showDocumentRequestURI.value = req.uri
            expectation.fulfill()
            return ShowDocumentResponse(success: true)
          }

          _ = try await project.testClient.send(request)

          try await fulfillmentOfOrThrow([expectation])

          let url = try XCTUnwrap(
            showDocumentRequestURI.value?.fileURL,
            "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )

          let fileContents = try String(contentsOf: url, encoding: .utf8)

          XCTAssertEqual(
            fileContents,
            """
            // MyMacroClient.swift @ 7:3 - 7:3
            @DictionaryStorageProperty

            // MyMacroClient.swift @ 8:3 - 8:3
            @DictionaryStorageProperty

            // MyMacroClient.swift @ 9:1 - 9:1
            var _storage: [String: Any] = [:]

            """,
            "File doesn't contain macro expansion. Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )

          XCTAssertEqual(
            url.lastPathComponent,
            "MyMacroClient.swift",
            "Failed for position range between \(positionMarker.start) and \(positionMarker.end)"
          )
        }
      }
    }
  }

  func testNestedMacroExpansion() async throws {
    try await SkipUnless.canBuildMacroUsingSwiftSyntaxFromSourceKitLSPBuild()
    try await SkipUnless.swiftPMSupportsExperimentalPrepareForIndexing()

    let files: [RelativeFileLocation: String] = [
      "MyMacros/MyMacros.swift": #"""

      import SwiftCompilerPlugin
      import SwiftSyntax
      import SwiftSyntaxBuilder
      import SwiftSyntaxMacros

      public struct OuterMacro: ExpressionMacro {
        public static func expansion(
          of node: some FreestandingMacroExpansionSyntax,
          in context: some MacroExpansionContext
        ) -> ExprSyntax {
          // Add padding to check that we use the outer macro expansion buffer's snapshot to do position conversions.
          return "/* padding */ #intermediate"
        }
      }

      public struct IntermediateMacro: ExpressionMacro {
        public static func expansion(
          of node: some FreestandingMacroExpansionSyntax,
          in context: some MacroExpansionContext
        ) -> ExprSyntax {
          return "#stringify(1 + 2)"
        }
      }

      public struct StringifyMacro: ExpressionMacro {
        public static func expansion(
          of node: some FreestandingMacroExpansionSyntax,
          in context: some MacroExpansionContext
        ) -> ExprSyntax {
          guard let argument = node.arguments.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
          }

          return "(\(argument), \(literal: argument.description))"
        }
      }

      @main
      struct MyMacroPlugin: CompilerPlugin {
        let providingMacros: [Macro.Type] = [
          OuterMacro.self,
          IntermediateMacro.self,
          StringifyMacro.self,
        ]
      }
      """#,
      "MyMacroClient/MyMacroClient.swift": """
      @freestanding(expression)
      public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "MyMacros", type: "StringifyMacro")

      @freestanding(expression)
      public macro intermediate() -> (Int, String) = #externalMacro(module: "MyMacros", type: "IntermediateMacro")

      @freestanding(expression)
      public macro outer() -> (Int, String) = #externalMacro(module: "MyMacros", type: "OuterMacro")

      func test() {
        1️⃣#outer
      }
      """,
    ]

    let project = try await SwiftPMTestProject(
      files: files,
      manifest: SwiftPMTestProject.macroPackageManifest,
      capabilities: ClientCapabilities(experimental: [
        "workspace/peekDocuments": .bool(true),
        "workspace/getReferenceDocument": .bool(true),
      ]),
      options: SourceKitLSPOptions.testDefault(),
      enableBackgroundIndexing: true
    )

    let (originalFileUri, positions) = try project.openDocument("MyMacroClient.swift")

    // Expand outer macro

    var outerExpandMacroCommand = ExpandMacroCommand(
      positionRange: Range(positions["1️⃣"]),
      textDocument: TextDocumentIdentifier(originalFileUri)
    ).asCommand()
    outerExpandMacroCommand.arguments?.append(
      SourceKitLSPCommandMetadata(textDocument: TextDocumentIdentifier(originalFileUri)).encodeToLSPAny()
    )

    let outerExpandMacroRequest = ExecuteCommandRequest(
      command: outerExpandMacroCommand.command,
      arguments: outerExpandMacroCommand.arguments
    )

    let outerPeekDocumentRequestReceived = self.expectation(description: "Outer PeekDocumentsRequest received")
    let outerPeekDocumentsRequestURIs = ThreadSafeBox<[DocumentURI]?>(initialValue: nil)

    project.testClient.handleSingleRequest { (req: PeekDocumentsRequest) in
      outerPeekDocumentsRequestURIs.value = req.locations
      outerPeekDocumentRequestReceived.fulfill()
      return PeekDocumentsResponse(success: true)
    }

    _ = try await project.testClient.send(outerExpandMacroRequest)
    try await fulfillmentOfOrThrow([outerPeekDocumentRequestReceived])

    let outerPeekDocumentURI = try XCTUnwrap(outerPeekDocumentsRequestURIs.value?.only)
    let outerMacroExpansion = try await project.testClient.send(GetReferenceDocumentRequest(uri: outerPeekDocumentURI))

    guard outerMacroExpansion.content == "/* padding */ #intermediate" else {
      XCTFail("Received unexpected macro expansion content: \(outerMacroExpansion.content)")
      return
    }

    // Expand intermediate macro

    var intermediateExpandMacroCommand = ExpandMacroCommand(
      positionRange: Range(Position(line: 0, utf16index: 14)),
      textDocument: TextDocumentIdentifier(outerPeekDocumentURI)
    ).asCommand()
    intermediateExpandMacroCommand.arguments?.append(
      SourceKitLSPCommandMetadata(textDocument: TextDocumentIdentifier(outerPeekDocumentURI)).encodeToLSPAny()
    )

    let intermediateExpandMacroRequest = ExecuteCommandRequest(
      command: intermediateExpandMacroCommand.command,
      arguments: intermediateExpandMacroCommand.arguments
    )

    let intermediatePeekDocumentRequestReceived = self.expectation(description: "Inner PeekDocumentsRequest received")
    let intermediatePeekDocumentsRequestURIs = ThreadSafeBox<[DocumentURI]?>(initialValue: nil)

    project.testClient.handleSingleRequest { (req: PeekDocumentsRequest) in
      intermediatePeekDocumentsRequestURIs.value = req.locations
      intermediatePeekDocumentRequestReceived.fulfill()
      return PeekDocumentsResponse(success: true)
    }

    _ = try await project.testClient.send(intermediateExpandMacroRequest)
    try await fulfillmentOfOrThrow([intermediatePeekDocumentRequestReceived])

    let intermediatePeekDocumentURI = try XCTUnwrap(intermediatePeekDocumentsRequestURIs.value?.only)
    let intermediateMacroExpansion = try await project.testClient.send(
      GetReferenceDocumentRequest(uri: intermediatePeekDocumentURI)
    )

    guard intermediateMacroExpansion.content == "#stringify(1 + 2)" else {
      XCTFail("Received unexpected macro expansion content: \(intermediateMacroExpansion.content)")
      return
    }

    // Expand inner macro

    var innerExpandMacroCommand = ExpandMacroCommand(
      positionRange: Range(Position(line: 0, utf16index: 0)),
      textDocument: TextDocumentIdentifier(intermediatePeekDocumentURI)
    ).asCommand()
    innerExpandMacroCommand.arguments?.append(
      SourceKitLSPCommandMetadata(textDocument: TextDocumentIdentifier(intermediatePeekDocumentURI)).encodeToLSPAny()
    )

    let innerExpandMacroRequest = ExecuteCommandRequest(
      command: innerExpandMacroCommand.command,
      arguments: innerExpandMacroCommand.arguments
    )

    let innerPeekDocumentRequestReceived = self.expectation(description: "Inner PeekDocumentsRequest received")
    let innerPeekDocumentsRequestURIs = ThreadSafeBox<[DocumentURI]?>(initialValue: nil)

    project.testClient.handleSingleRequest { (req: PeekDocumentsRequest) in
      innerPeekDocumentsRequestURIs.value = req.locations
      innerPeekDocumentRequestReceived.fulfill()
      return PeekDocumentsResponse(success: true)
    }

    _ = try await project.testClient.send(innerExpandMacroRequest)
    try await fulfillmentOfOrThrow([innerPeekDocumentRequestReceived])

    let innerPeekDocumentURI = try XCTUnwrap(innerPeekDocumentsRequestURIs.value?.only)
    let innerMacroExpansion = try await project.testClient.send(GetReferenceDocumentRequest(uri: innerPeekDocumentURI))

    XCTAssertEqual(innerMacroExpansion.content, #"(1 + 2, "1 + 2")"#)
  }
}
