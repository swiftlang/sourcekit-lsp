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
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import SKUtilities
import SwiftExtensions
import TSCBasic
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

final class WorkspaceSymbolInfoTests: XCTestCase {
  /// Returns the first `WorkspaceSymbol` in a `workspaceSymbolInfo` response for `name` whose location is a
  /// URI-only `sourcekit-lsp://generated-swift-interface` reference-document location (no range).
  private func generatedInterfaceSymbol(
    for name: String,
    in response: WorkspaceSymbolInfoResponse
  ) -> WorkspaceSymbol? {
    for case .workspaceSymbol(let symbol) in response.results {
      if symbol.name == name,
        case .uri(let uriOnly) = symbol.location,
        let components = URLComponents(string: uriOnly.uri.arbitrarySchemeURL.absoluteString),
        components.scheme == "sourcekit-lsp",
        components.host == "generated-swift-interface"
      {
        return symbol
      }
    }
    return nil
  }

  func testWorkspaceSymbolNamesContainsSourceSymbols() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      public struct MyStruct {}
      public func myFunction() {}
      """,
      indexSystemModules: true
    )

    let response = try await project.testClient.send(WorkspaceSymbolNamesRequest())

    assertContains(response.names, "MyStruct")
    assertContains(response.names, "myFunction()")
    // Stdlib types should be included as it's implicitly imported.
    assertContains(response.names, "String")
  }

  func testWorkspaceSymbolInfoAndResolveForStdlibSymbol() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      let x: String = ""
      """,
      capabilities: ClientCapabilities(
        workspace: .init(symbol: .init(resolveSupport: .init(properties: ["location"]))),
        experimental: [GetReferenceDocumentRequest.method: .dictionary(["supported": .bool(true)])]
      ),
      indexSystemModules: true
    )

    let response = try await project.testClient.send(WorkspaceSymbolInfoRequest(names: ["String"]))

    // workspace/symbolInfo returns SDK symbols as a `WorkspaceSymbol` whose location is the URI-only form of
    // a `sourcekit-lsp://generated-swift-interface` reference document (no range), with a `sourceKitData`.
    let symbol = try XCTUnwrap(
      generatedInterfaceSymbol(for: "String", in: response),
      "Expected a 'String' WorkspaceSymbol with a generated-interface reference-document URI"
    )
    guard case .uri(let uriOnly) = symbol.location else {
      XCTFail("Expected .uri location, got \(symbol.location)")
      return
    }
    XCTAssertEqual(uriOnly.uri.scheme, "sourcekit-lsp")
    let urlComponents = try XCTUnwrap(URLComponents(string: uriOnly.uri.arbitrarySchemeURL.absoluteString))
    let moduleParam = try XCTUnwrap(
      urlComponents.queryItems?.first(where: { $0.name == "moduleName" })?.value,
      "URI should contain a moduleName query parameter"
    )
    XCTAssertFalse(moduleParam.isEmpty, "moduleName query parameter should be non-empty")

    // The interface path and module name are also carried in `sourceKitData`.
    let sourceKitData = try XCTUnwrap(symbol.sourceKitData, "Expected SourceKitWorkspaceSymbolData in data")
    let dataModuleName = try XCTUnwrap(sourceKitData.moduleName, "Expected a moduleName in data")
    XCTAssert(dataModuleName.hasPrefix("Swift"), "Expected module name starting with 'Swift', got \(dataModuleName)")
    let dataInterfaceURI = try XCTUnwrap(sourceKitData.interfaceURI, "Expected an interfaceURI in data")
    XCTAssert(
      dataInterfaceURI.pseudoPath.hasSuffix(".swiftinterface") || dataInterfaceURI.pseudoPath.hasSuffix(".swiftmodule"),
      "Expected interfaceURI to point at a .swiftinterface/.swiftmodule, got \(dataInterfaceURI)"
    )

    // workspaceSymbol/resolve fills in the range.
    let resolved = try await project.testClient.send(
      WorkspaceSymbolResolveRequest(workspaceSymbol: symbol)
    )
    guard case .location(let location) = resolved.location else {
      XCTFail("Expected .location after resolve, got \(resolved.location)")
      return
    }
    XCTAssertEqual(location.uri, uriOnly.uri, "resolve must not change the URI, only fill in the range")

    // getReferenceDocument delivers the interface text; the resolved range points at the declaration.
    let refDoc = try await project.testClient.send(GetReferenceDocumentRequest(uri: location.uri))
    XCTAssert(
      refDoc.content.contains("struct String"),
      "Generated interface should contain 'struct String'"
    )
    let lineTable = LineTable(refDoc.content)
    let line = try XCTUnwrap(lineTable.line(at: location.range.lowerBound.line))
      .trimmingCharacters(in: .whitespaces)
    XCTAssert(
      line.contains("struct String"),
      "Line at resolved position should contain 'struct String', got: '\(line)'"
    )
  }

  func testWorkspaceSymbolInfoStdlibSymbolFallsBackToFileLocationWithoutReferenceDocumentSupport() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      let x: String = ""
      """,
      // No `workspaceSymbol/resolve` and no generated-interface reference-document support.
      capabilities: ClientCapabilities(),
      indexSystemModules: true
    )

    let response = try await project.testClient.send(WorkspaceSymbolInfoRequest(names: ["String"]))

    // Without reference-document + resolve support, the SDK symbol falls back to a plain
    // `SymbolInformation` pointing directly at its `.swiftinterface`/`.swiftmodule` file.
    let interfaceLocation = response.results.lazy.compactMap { item -> Location? in
      guard case .symbolInformation(let info) = item, info.name == "String" else { return nil }
      return info.location
    }.first { location in
      guard let path = location.uri.fileURL?.path else { return false }
      return path.hasSuffix(".swiftinterface") || path.hasSuffix(".swiftmodule")
    }
    XCTAssertNotNil(
      interfaceLocation,
      "Expected a 'String' SymbolInformation with a .swiftinterface/.swiftmodule file:// location"
    )

    // No generated-interface reference-document URI should be emitted.
    XCTAssertNil(
      generatedInterfaceSymbol(for: "String", in: response),
      "Should not emit a reference-document URI without reference-document support"
    )
  }

  /// Confirms that symbols from a binary-only `.swiftmodule` (compiled without `-index-store-path`)
  /// do not appear in the workspace index, unlike symbols from source-compiled targets.
  func testBinarySwiftModuleSymbolsNotIndexed() async throws {
    guard let swiftc = await ToolchainRegistry.forTesting.default?.swiftc else {
      throw XCTSkip("swiftc not found")
    }

    // Compile a Swift module to binary .swiftmodule only — no -index-store-path,
    // so its symbols are never written to any index store.
    try await withTestScratchDir { binaryModuleDir in
      let sourceFile = binaryModuleDir.appendingPathComponent("BinaryLib.swift")
      try await "public struct BinaryOnlyStruct {}".writeWithRetry(to: sourceFile)

      var args = [
        swiftc.path,
        "-emit-module",
        "-module-name", "BinaryLib",
        "-emit-module-path", binaryModuleDir.appendingPathComponent("BinaryLib.swiftmodule").path,
      ]
      if let sdk = defaultSDKPath {
        args += ["-sdk", sdk]
      }
      // Pin the deployment target to macOS 10.13 to match SwiftPMTestProject's default,
      // so the binary module is importable in the consumer project regardless of SDK version.
      #if os(macOS)
      #if arch(arm64)
      args += ["-target", "arm64-apple-macosx10.13"]
      #elseif arch(x86_64)
      args += ["-target", "x86_64-apple-macosx10.13"]
      #endif
      #endif
      args += [sourceFile.path]
      try await Process.checkNonZeroExit(arguments: args)

      // Create a project that imports BinaryLib via its binary .swiftmodule only.
      let project = try await SwiftPMTestProject(
        files: [
          "Sources/App/main.swift": """
          import BinaryLib
          public struct SourceStruct {
            var binary: BinaryOnlyStruct
          }
          """
        ],
        manifest: """
          let package = Package(
            name: "App",
            targets: [
              .executableTarget(
                name: "App",
                swiftSettings: [.unsafeFlags(["-I", "\(binaryModuleDir.path)"])]
              )
            ]
          )
          """,
        enableBackgroundIndexing: true,
        pollIndex: true
      )
      XCTAssert(FileManager.default.fileExists(at: binaryModuleDir.appendingPathComponent("BinaryLib.swiftmodule")))

      // Confirm the file has no error diagnostics — the binary .swiftmodule is importable.
      let (mainUri, _) = try project.openDocument("main.swift")
      let diagnostics = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(mainUri))
      )
      let errorDiagnostics = diagnostics.fullReport?.items.filter { $0.severity == .error } ?? []
      XCTAssert(errorDiagnostics.isEmpty, "Expected no errors in main.swift, got: \(errorDiagnostics)")

      let response = try await project.testClient.send(WorkspaceSymbolNamesRequest())

      // SourceStruct is defined in source and compiled with -index-store-path → it IS indexed.
      XCTAssert(response.names.contains("SourceStruct"), "Source-compiled symbol should appear in the index")

      // BinaryOnlyStruct lives only in the .swiftmodule binary → no index record was ever written for it.
      XCTAssertFalse(
        response.names.contains("BinaryOnlyStruct"),
        "Symbol from binary-only .swiftmodule should not appear in the index"
      )
    }
  }
}
