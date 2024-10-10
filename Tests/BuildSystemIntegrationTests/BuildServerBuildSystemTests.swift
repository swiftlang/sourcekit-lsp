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

import BuildServerProtocol
import BuildSystemIntegration
import Foundation
import ISDBTestSupport
import LanguageServerProtocol
import SKSupport
import SKTestSupport
import TSCBasic
import XCTest

final class BuildServerBuildSystemTests: XCTestCase {
  func testBuildSettingsFromBuildServer() async throws {
    let project = try await BuildServerTestProject(
      files: [
        "Test.swift": """
        #if DEBUG
        #error("DEBUG SET")
        #else
        #error("DEBUG NOT SET")
        #endif
        """
      ],
      buildServer: """
        class BuildServer(AbstractBuildServer):
          def workspace_build_targets(self, request: Dict[str, object]) -> Dict[str, object]:
            return {
              "targets": [
                {
                  "id": {"uri": "bsp://dummy"},
                  "tags": [],
                  "languageIds": [],
                  "dependencies": [],
                  "capabilities": {},
                }
              ]
            }

          def buildtarget_sources(self, request: Dict[str, object]) -> Dict[str, object]:
            return {
              "items": [
                {
                  "target": {"uri": "bsp://dummy"},
                  "sources": [
                    {"uri": "$TEST_DIR_URL/Test.swift", "kind": 1, "generated": False}
                  ],
                }
              ]
            }

          def textdocument_sourcekitoptions(self, request: Dict[str, object]) -> Dict[str, object]:
            return {
              "compilerArguments": ["$TEST_DIR/Test.swift", "-DDEBUG", $SDK_ARGS]
            }
        """
    )

    let (uri, _) = try project.openDocument("Test.swift")

    try await repeatUntilExpectedResult {
      let diags = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diags.fullReport?.items.map(\.message) == ["DEBUG SET"]
    }
  }

  func testBuildTargetsChanged() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await BuildServerTestProject(
      files: [
        "Test.swift": """
        #if DEBUG
        #error("DEBUG SET")
        #else
        #error("DEBUG NOT SET")
        #endif
        """
      ],
      buildServer: """
        import threading

        class BuildServer(AbstractBuildServer):
          timer_has_fired: bool = False

          def timer_fired(self):
            self.timer_has_fired = True
            self.send_notification("buildTarget/didChange", {})

          def workspace_build_targets(self, request: Dict[str, object]) -> Dict[str, object]:
            if self.timer_has_fired:
              return {
                "targets": [
                  {
                    "id": {"uri": "bsp://dummy"},
                    "tags": [],
                    "languageIds": [],
                    "dependencies": [],
                    "capabilities": {},
                  }
                ]
              }
            else:
              threading.Timer(1, self.timer_fired).start()
              return {"targets": []}

          def buildtarget_sources(self, request: Dict[str, object]) -> Dict[str, object]:
            assert self.timer_has_fired
            return {
              "items": [
                {
                  "target": {"uri": "bsp://dummy"},
                  "sources": [
                    {"uri": "$TEST_DIR_URL/Test.swift", "kind": 1, "generated": False}
                  ],
                }
              ]
            }

          def textdocument_sourcekitoptions(self, request: Dict[str, object]) -> Dict[str, object]:
            assert self.timer_has_fired
            return {
              "compilerArguments": ["$TEST_DIR/Test.swift", "-DDEBUG", $SDK_ARGS]
            }
        """
    )

    let (uri, _) = try project.openDocument("Test.swift")

    // Initially, we shouldn't have any diagnostics because Test.swift is not part of any target
    let initialDiagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(initialDiagnostics.fullReport?.items, [])

    // But then the 1s timer in the build server should fire, we get a `buildTarget/didChange` notification and we have
    // build settings for Test.swift
    try await repeatUntilExpectedResult {
      let diags = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diags.fullReport?.items.map(\.message) == ["DEBUG SET"]
    }
  }

  func testSettingsOfSingleFileChanged() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await BuildServerTestProject(
      files: [
        "Test.swift": """
        #if DEBUG
        #error("DEBUG SET")
        #else
        #error("DEBUG NOT SET")
        #endif
        """
      ],
      buildServer: """
        import threading

        class BuildServer(AbstractBuildServer):
          timer_has_fired: bool = False

          def timer_fired(self):
            self.timer_has_fired = True
            self.send_notification("buildTarget/didChange", {})

          def workspace_build_targets(self, request: Dict[str, object]) -> Dict[str, object]:
            return {
              "targets": [
                {
                  "id": {"uri": "bsp://dummy"},
                  "tags": [],
                  "languageIds": [],
                  "dependencies": [],
                  "capabilities": {},
                }
              ]
            }

          def buildtarget_sources(self, request: Dict[str, object]) -> Dict[str, object]:
            return {
              "items": [
                {
                  "target": {"uri": "bsp://dummy"},
                  "sources": [
                    {"uri": "$TEST_DIR_URL/Test.swift", "kind": 1, "generated": False}
                  ],
                }
              ]
            }

          def textdocument_sourcekitoptions(self, request: Dict[str, object]) -> Dict[str, object]:
            if self.timer_has_fired:
              return {
                "compilerArguments": ["$TEST_DIR/Test.swift", "-DDEBUG", $SDK_ARGS]
              }
            else:
              threading.Timer(1, self.timer_fired).start()
              return {
                "compilerArguments": ["$TEST_DIR/Test.swift", $SDK_ARGS]
              }
        """
    )

    let (uri, _) = try project.openDocument("Test.swift")

    // Initially, we don't have -DDEBUG set, so we should get `DEBUG NOT SET`
    let initialDiagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(initialDiagnostics.fullReport?.items.map(\.message), ["DEBUG NOT SET"])

    // But then the 1s timer in the build server should fire, we get a `buildTarget/didChange` notification and we get
    // build settings for Test.swift that include -DDEBUG
    try await repeatUntilExpectedResult {
      let diags = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diags.fullReport?.items.map(\.message) == ["DEBUG SET"]
    }
  }

  func testCrashRecovery() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await BuildServerTestProject(
      files: [
        "Crash.swift": "",
        "Test.swift": """
        #if DEBUG
        #error("DEBUG SET")
        #else
        #error("DEBUG NOT SET")
        #endif
        """,
        "should_crash": "dummy file to indicate that BSP server should crash",
      ],
      buildServer: """
        import threading
        import os

        class BuildServer(AbstractBuildServer):
          def workspace_build_targets(self, request: Dict[str, object]) -> Dict[str, object]:
            return {
              "targets": [
                {
                  "id": {"uri": "bsp://dummy"},
                  "tags": [],
                  "languageIds": [],
                  "dependencies": [],
                  "capabilities": {},
                }
              ]
            }

          def buildtarget_sources(self, request: Dict[str, object]) -> Dict[str, object]:
            return {
              "items": [
                {
                  "target": {"uri": "bsp://dummy"},
                  "sources": [
                    {"uri": "$TEST_DIR_URL/Crash.swift", "kind": 1, "generated": False},
                    {"uri": "$TEST_DIR_URL/Test.swift", "kind": 1, "generated": False},
                  ],
                }
              ]
            }

          def textdocument_sourcekitoptions(self, request: Dict[str, object]) -> Dict[str, object]:
            if os.path.exists("$TEST_DIR/should_crash"):
              assert False
            return {
              "compilerArguments": ["$TEST_DIR/Test.swift", "-DDEBUG", $SDK_ARGS]
            }
        """
    )

    // Check that we still get results for Test.swift (after relaunching the BSP server)
    let (uri, _) = try project.openDocument("Test.swift")

    // While the BSP server is crashing, we shouldn't get any build settings and thus get empty diagnostics.
    let diagnosticsBeforeCrash = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(diagnosticsBeforeCrash.fullReport?.items, [])
    try FileManager.default.removeItem(at: project.scratchDirectory.appendingPathComponent("should_crash"))

    try await repeatUntilExpectedResult(timeout: .seconds(20)) {
      let diagnostics = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diagnostics.fullReport?.items.map(\.message) == ["DEBUG SET"]
    }

  }
}
