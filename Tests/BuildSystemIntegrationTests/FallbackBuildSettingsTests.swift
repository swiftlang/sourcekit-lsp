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

import BuildServerProtocol
@_spi(Testing) import BuildSystemIntegration
import LanguageServerProtocol
import SKOptions
import SKTestSupport
import SourceKitLSP
import TSCBasic
import XCTest

import struct PackageModel.BuildFlags

final class FallbackBuildSystemTests: XCTestCase {

  func testSwift() throws {
    let sdk = "/my/sdk"
    let source = DocumentURI(filePath: "/my/source.swift", isDirectory: false)

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .swift, options: .init(sdk: sdk)),
      FileBuildSettings(compilerArguments: ["-sdk", sdk, source.pseudoPath], workingDirectory: nil, isFallback: true)
    )
  }

  func testSwiftWithCustomFlags() throws {
    let sdk = "/my/sdk"
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
    let sdk = "/my/sdk"
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
    let sdk = "/my/sdk"
    let source = DocumentURI(filePath: "/my/source.cpp", isDirectory: false)

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .cpp, options: .init(sdk: sdk)),
      FileBuildSettings(
        compilerArguments: ["-isysroot", sdk, source.pseudoPath],
        workingDirectory: nil,
        isFallback: true
      )
    )
  }

  func testCXXWithCustomFlags() throws {
    let sdk = "/my/sdk"
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
    let sdk = "/my/sdk"
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
    let sdk = "/my/sdk"
    let source = DocumentURI(filePath: "/my/source.c", isDirectory: false)

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .c, options: .init(sdk: sdk))?.compilerArguments,
      ["-isysroot", sdk, source.pseudoPath]
    )
  }

  func testCWithCustomFlags() throws {
    let sdk = "/my/sdk"
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
    let sdk = "/my/sdk"
    let source = DocumentURI(filePath: "/my/source.m", isDirectory: false)

    XCTAssertEqual(
      fallbackBuildSettings(for: source, language: .objective_c, options: .init(sdk: sdk))?.compilerArguments,
      ["-isysroot", sdk, source.pseudoPath]
    )
  }

  func testObjCXX() throws {
    let sdk = "/my/sdk"
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

  func testFallbackBuildSettingsWhileBuildSystemIsComputingBuildSettings() async throws {
    let fallbackResultsReceived = WrappedSemaphore(name: "Fallback results received")
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        let x: 1️⃣String = 1
        """
      ],
      testHooks: TestHooks(
        buildSystemTestHooks: BuildSystemTestHooks(
          handleRequest: { request in
            if request is TextDocumentSourceKitOptionsRequest {
              fallbackResultsReceived.waitOrXCTFail()
            }
          }
        )
      )
    )

    let (uri, positions) = try project.openDocument("Test.swift")

    let diagsBeforeBuildSettings = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(diagsBeforeBuildSettings.fullReport?.items, [])

    let hoverBeforeBuildSettings = try await project.testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertNotNil(hoverBeforeBuildSettings?.contents)

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
