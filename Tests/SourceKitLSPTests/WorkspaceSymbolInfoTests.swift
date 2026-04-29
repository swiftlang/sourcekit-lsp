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
import XCTest

final class WorkspaceSymbolInfoTests: XCTestCase {
  /// Returns the first `WorkspaceSymbol` in a `workspaceSymbolInfo` response for `name` whose
  /// location is a `file://` URI to a module file (`.swiftinterface` or `.swiftmodule`).
  private func generatedInterfaceSymbol(
    for name: String,
    in response: WorkspaceSymbolInfoResponse
  ) -> WorkspaceSymbol? {
    for case .workspaceSymbol(let symbol) in response.results {
      if symbol.name == name,
        case .uri(let uriOnly) = symbol.location,
        let path = uriOnly.uri.fileURL?.path,
        path.hasSuffix(".swiftinterface") || path.hasSuffix(".swiftmodule")
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

    // workspace/symbolInfo returns a deferred WorkspaceSymbol for SDK symbols:
    // location is a file://<module-file>?module=<name> URI (no range), USR in data["usr"].
    let symbol = try XCTUnwrap(
      generatedInterfaceSymbol(for: "String", in: response),
      "Expected a 'String' WorkspaceSymbol with a module file URI location"
    )
    guard case .uri(let uriOnly) = symbol.location else {
      XCTFail("Expected .uri location, got \(symbol.location)")
      return
    }
    let path = try XCTUnwrap(uriOnly.uri.fileURL?.path)
    XCTAssert(
      path.hasSuffix(".swiftinterface") || path.hasSuffix(".swiftmodule"),
      "Expected a .swiftinterface or .swiftmodule path, got: \(path)"
    )
    let urlComponents = try XCTUnwrap(URLComponents(string: uriOnly.uri.arbitrarySchemeURL.absoluteString))
    let queryItems = urlComponents.queryItems
    let moduleParam = try XCTUnwrap(
      queryItems?.first(where: { $0.name == "module" })?.value,
      "URI should contain a ?module= query parameter"
    )
    XCTAssertFalse(moduleParam.isEmpty, "?module= query parameter should be non-empty")
    XCTAssertNil(urlComponents.fragment, "URI should not contain a fragment")

    // workspaceSymbol/resolve turns the deferred URI into a sourcekit-lsp:// location with a range.
    let resolved = try await project.testClient.send(
      WorkspaceSymbolResolveRequest(workspaceSymbol: symbol)
    )
    guard case .location(let location) = resolved.location else {
      XCTFail("Expected .location after resolve, got \(resolved.location)")
      return
    }
    XCTAssertEqual(location.uri.scheme, "sourcekit-lsp")

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
      try "public struct BinaryOnlyStruct {}".write(to: sourceFile, atomically: true, encoding: .utf8)

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
