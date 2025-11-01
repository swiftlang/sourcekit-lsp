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

@_spi(Testing) import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKOptions
import SKTestSupport
import SourceKitLSP
import TSCBasic
import XCTest

final class FallbackBuildServerTests: SourceKitLSPTestCase {
  func testSwift() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.swift", isDirectory: false)

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .swift, options: .init(sdk: sdk)),
      FileBuildSettings(
        compilerArguments: ["-sdk", sdk, source.pseudoPath],
        workingDirectory: nil,
        language: .swift,
        isFallback: true
      )
    )
  }

  func testSwiftWithCustomFlags() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.swift", isDirectory: false)

    let options = SourceKitLSPOptions.FallbackBuildSystemOptions(
      swiftCompilerFlags: [
        "-Xfrontend",
        "-debug-constraints",
      ],
      sdk: sdk
    )
    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .swift, options: options)?.compilerArguments,
      ["-Xfrontend", "-debug-constraints", "-sdk", sdk, source.pseudoPath]
    )
  }

  func testSwiftWithCustomSDKFlag() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.swift", isDirectory: false)

    let options = SourceKitLSPOptions.FallbackBuildSystemOptions(
      swiftCompilerFlags: ["-sdk", "/some/custom/sdk", "-Xfrontend", "-debug-constraints"],
      sdk: sdk
    )
    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .swift, options: options)?.compilerArguments,
      ["-sdk", "/some/custom/sdk", "-Xfrontend", "-debug-constraints", source.pseudoPath]
    )
  }

  func testCXX() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.cpp", isDirectory: false)

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .cpp, options: .init(sdk: sdk)),
      FileBuildSettings(
        compilerArguments: ["-isysroot", sdk, source.pseudoPath],
        workingDirectory: nil,
        language: .cpp,
        isFallback: true
      )
    )
  }

  func testCXXWithCustomFlags() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.cpp", isDirectory: false)

    let options = SourceKitLSPOptions.FallbackBuildSystemOptions(
      cxxCompilerFlags: ["-v"],
      sdk: sdk
    )

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .cpp, options: options)?.compilerArguments,
      ["-v", "-isysroot", sdk, source.pseudoPath]
    )
  }

  func testCXXWithCustomIsysroot() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.cpp", isDirectory: false)

    let options = SourceKitLSPOptions.FallbackBuildSystemOptions(
      cxxCompilerFlags: [
        "-isysroot",
        "/my/custom/sdk",
        "-v",
      ],
      sdk: sdk
    )

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .cpp, options: options)?.compilerArguments,
      ["-isysroot", "/my/custom/sdk", "-v", source.pseudoPath]
    )
  }

  func testC() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.c", isDirectory: false)

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .c, options: .init(sdk: sdk))?.compilerArguments,
      ["-isysroot", sdk, source.pseudoPath]
    )
  }

  func testCWithCustomFlags() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.c", isDirectory: false)

    let options = SourceKitLSPOptions.FallbackBuildSystemOptions(
      cCompilerFlags: ["-v"],
      sdk: sdk
    )

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .c, options: options)?.compilerArguments,
      ["-v", "-isysroot", sdk, source.pseudoPath]
    )
  }

  func testObjC() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.m", isDirectory: false)

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .objective_c, options: .init(sdk: sdk))?.compilerArguments,
      ["-isysroot", sdk, source.pseudoPath]
    )
  }

  func testObjCXX() throws {
    let sdk = try AbsolutePath(validating: "/my/sdk").pathString
    let source = DocumentURI(filePath: "/my/source.mm", isDirectory: false)

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .objective_cpp, options: .init(sdk: sdk))?.compilerArguments,
      ["-isysroot", sdk, source.pseudoPath]
    )
  }

  func testUnknown() throws {
    let source = DocumentURI(filePath: "/my/source.mm", isDirectory: false)

    XCTAssertNil(fallbackBuildSettings(for: source, language: Language(rawValue: "unknown"), options: .init()))
  }

  func testFallbackBuildSettingsWhileBuildServerIsComputingBuildSettings() async throws {
    let fallbackResultsReceived = WrappedSemaphore(name: "Fallback results received")
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        let x: 1️⃣String2️⃣ = 1
        """
      ],
      hooks: Hooks(
        buildServerHooks: BuildServerHooks(
          preHandleRequest: { request in
            if request is TextDocumentSourceKitOptionsRequest {
              fallbackResultsReceived.waitOrXCTFail()
            }
          }
        )
      )
    )

    let (uri, positions) = try project.openDocument("Test.swift")

    let documentHighlight = try await project.testClient.send(
      DocumentHighlightRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(documentHighlight, [DocumentHighlight(range: positions["1️⃣"]..<positions["2️⃣"], kind: .read)])

    fallbackResultsReceived.signal()

    try await repeatUntilExpectedResult {
      let diagsAfterBuildSettings = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diagsAfterBuildSettings.fullReport?.items.map(\.message) == [
        "Cannot convert value of type 'Int' to specified type 'String'"
      ]
    }
  }
}
