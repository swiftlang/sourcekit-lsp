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

import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
import SKLogging
import SKOptions
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
import TSCBasic
import XCTest

#if os(Windows)
import WinSDK
#endif

final class ExternalBuildServerTests: SourceKitLSPTestCase {
  func testBuildSettingsFromBuildServer() async throws {
    let project = try await ExternalBuildServerTestProject(
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
              "compilerArguments": [r"$TEST_DIR/Test.swift", "-DDEBUG", $SDK_ARGS]
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

    let project = try await ExternalBuildServerTestProject(
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
          has_changed_targets: bool = False

          def workspace_build_targets(self, request: Dict[str, object]) -> Dict[str, object]:
            if self.has_changed_targets:
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
              return {"targets": []}

          def buildtarget_sources(self, request: Dict[str, object]) -> Dict[str, object]:
            assert self.has_changed_targets
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
            assert self.has_changed_targets
            return {
              "compilerArguments": [r"$TEST_DIR/Test.swift", "-DDEBUG", $SDK_ARGS]
            }

          def workspace_did_change_watched_files(self, notification: Dict[str, object]) -> None:
            self.has_changed_targets = True
            self.send_notification("buildTarget/didChange", {})
        """
    )

    let (uri, _) = try project.openDocument("Test.swift")

    // Initially, we shouldn't have any diagnostics because Test.swift is not part of any target
    let initialDiagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(initialDiagnostics.fullReport?.items, [])

    // We use an arbitrary file change to signal to the BSP server that it should send the targets changed notification
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: try DocumentURI(string: "file:///dummy"), type: .created)
      ])
    )

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

    let project = try await ExternalBuildServerTestProject(
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
          has_changed_settings: bool = False

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
            if self.has_changed_settings:
              return {
                "compilerArguments": [r"$TEST_DIR/Test.swift", "-DDEBUG", $SDK_ARGS]
              }
            else:
              return {
                "compilerArguments": [r"$TEST_DIR/Test.swift", $SDK_ARGS]
              }

          def workspace_did_change_watched_files(self, notification: Dict[str, object]) -> None:
            self.has_changed_settings = True
            self.send_notification("buildTarget/didChange", {})
        """
    )

    let (uri, _) = try project.openDocument("Test.swift")

    // Initially, we don't have -DDEBUG set, so we should get `DEBUG NOT SET`
    let initialDiagnostics = try await project.testClient.send(
      DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(initialDiagnostics.fullReport?.items.map(\.message), ["DEBUG NOT SET"])

    // We use an arbitrary file change to signal to the BSP server that it should send the targets changed notification
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: try DocumentURI(string: "file:///dummy"), type: .created)
      ])
    )

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

    let project = try await ExternalBuildServerTestProject(
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
            if os.path.exists(r"$TEST_DIR/should_crash"):
              assert False
            return {
              "compilerArguments": [r"$TEST_DIR/Test.swift", "-DDEBUG", $SDK_ARGS]
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
    try FileManager.default.removeItem(at: project.scratchDirectory.appending(component: "should_crash"))

    try await repeatUntilExpectedResult(timeout: .seconds(20)) {
      let diagnostics = try await project.testClient.send(
        DocumentDiagnosticsRequest(textDocument: TextDocumentIdentifier(uri))
      )
      return diagnostics.fullReport?.items.map(\.message) == ["DEBUG SET"]
    }
  }

  func testBuildServerConfigAtLegacyLocation() async throws {
    let project = try await ExternalBuildServerTestProject(
      files: [
        "Test.swift": """
        #if DEBUG
        #error("DEBUG SET")
        #else
        #error("DEBUG NOT SET")
        #endif
        """
      ],
      buildServerConfigLocation: "buildServer.json",
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
              "compilerArguments": [r"$TEST_DIR/Test.swift", "-DDEBUG", $SDK_ARGS]
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

  func testBuildSettingsDataPassThrough() async throws {
    let project = try await ExternalBuildServerTestProject(
      files: [
        "Test.swift": ""
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
              "compilerArguments": [r"$TEST_DIR/Test.swift"],
              "data": {"custom": "value"}
            }
        """,
      options: .testDefault(experimentalFeatures: [.sourceKitOptionsRequest])
    )

    let (uri, _) = try project.openDocument("Test.swift")

    let options = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri),
        prepareTarget: false,
        allowFallbackSettings: false
      )
    )
    XCTAssertEqual(options.data, LSPAny.dictionary(["custom": .string("value")]))
  }

  func testBuildSettingsForFilePartOfMultipleTargets() async throws {
    let project = try await ExternalBuildServerTestProject(
      files: [
        "Test.swift": ""
      ],
      buildServer: """
        class BuildServer(AbstractBuildServer):
          def workspace_build_targets(self, request: Dict[str, object]) -> Dict[str, object]:
            return {
              "targets": [
                {
                  "id": {"uri": "bsp://first"},
                  "tags": [],
                  "languageIds": [],
                  "dependencies": [],
                  "capabilities": {},
                },
                {
                  "id": {"uri": "bsp://second"},
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
                  "target": {"uri": "bsp://first"},
                  "sources": [
                    {"uri": "$TEST_DIR_URL/Test.swift", "kind": 1, "generated": False}
                  ],
                },
                {
                  "target": {"uri": "bsp://second"},
                  "sources": [
                    {"uri": "$TEST_DIR_URL/Test.swift", "kind": 1, "generated": False}
                  ],
                }
              ]
            }

          def textdocument_sourcekitoptions(self, request: Dict[str, object]) -> Dict[str, object]:
            target_uri = request["target"]["uri"]
            if target_uri == "bsp://first":
              return {
                "compilerArguments": [r"$TEST_DIR/Test.swift", "-DFIRST"]
              }
            elif target_uri == "bsp://second":
              return {
                "compilerArguments": [r"$TEST_DIR/Test.swift", "-DSECOND"]
              }
            else:
              assert False, f"Unknown target {target_uri}"
        """,
      options: .testDefault(experimentalFeatures: [.sourceKitOptionsRequest])
    )

    let (uri, _) = try project.openDocument("Test.swift")

    let firstOptions = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri),
        target: DocumentURI(string: "bsp://first"),
        prepareTarget: false,
        allowFallbackSettings: false
      )
    )
    assertContains(try XCTUnwrap(firstOptions).compilerArguments, "-DFIRST")

    let secondOptions = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri),
        target: DocumentURI(string: "bsp://second"),
        prepareTarget: false,
        allowFallbackSettings: false
      )
    )
    assertContains(try XCTUnwrap(secondOptions).compilerArguments, "-DSECOND")

    let optionsWithoutTarget = try await project.testClient.send(
      SourceKitOptionsRequest(
        textDocument: TextDocumentIdentifier(uri),
        prepareTarget: false,
        allowFallbackSettings: false
      )
    )
    // We currently pick the canonical target alphabetically, which means that `bsp://first` wins over `bsp://second`
    assertContains(try XCTUnwrap(optionsWithoutTarget).compilerArguments, "-DFIRST")
  }

  func testDontBlockBuildServerInitializationIfBuildServerIsUnresponsive() async throws {
    // A build server that responds to the initialize request but not to any other requests.
    final class UnresponsiveBuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()

      init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {}

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        #if os(Windows)
        Sleep(60 * 60 * 1000 /*ms*/)
        #else
        sleep(60 * 60 /*s*/)
        #endif
        XCTFail("Build server should be terminated before finishing the timeout")
        throw ResponseError.methodNotFound(BuildTargetSourcesRequest.method)
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        #if os(Windows)
        Sleep(60 * 60 * 1000 /*ms*/)
        #else
        sleep(60 * 60 /*s*/)
        #endif
        XCTFail("Build server should be terminated before finishing the timeout")
        throw ResponseError.methodNotFound(TextDocumentSourceKitOptionsRequest.method)
      }
    }

    // Creating the `CustomBuildServerTestProject` waits for the initialize response and times out if it doesn't receive one.
    // Make sure that we get that response back.
    _ = try await CustomBuildServerTestProject(
      files: ["Test.swift": ""],
      buildServer: UnresponsiveBuildServer.self
    )
  }

  func testShutdownHangs() async throws {
    let startTime = Date()
    do {
      _ = try await ExternalBuildServerTestProject(
        files: [
          "Test.swift": ""
        ],
        buildServer: """
          import time

          class BuildServer(AbstractBuildServer):
            def workspace_build_targets(self, request: Dict[str, object]) -> Dict[str, object]:
              return { "targets": [] }

            def buildtarget_sources(self, request: Dict[str, object]) -> Dict[str, object]:
              return { "items": [] }

            def shutdown(self, request: Dict[str, object]) -> Dict[str, object]:
              time.sleep(60)
              assert False
          """,
        options: .testDefault(experimentalFeatures: [.sourceKitOptionsRequest])
      )
    }
    // Check that we didn't wait the full 60 seconds for the build server to shut down and instead terminated it.
    XCTAssert(Date().timeIntervalSince(startTime) < 50)
  }

  func testCancelPreparationOnLspShutdown() async throws {
    actor BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      private let projectRoot: URL
      let preparationStarted: XCTestExpectation
      let preparationFinished: XCTestExpectation

      init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
        self.projectRoot = projectRoot
        self.preparationStarted = XCTestExpectation(description: "Preparation started")
        self.preparationFinished = XCTestExpectation(description: "Preparation finished")
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        return try initializationResponseSupportingBackgroundIndexing(
          projectRoot: projectRoot,
          outputPathsProvider: false
        )
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) -> BuildTargetSourcesResponse {
        return dummyTargetSourcesResponse(files: [DocumentURI(projectRoot.appending(component: "Test.swift"))])
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) -> TextDocumentSourceKitOptionsResponse? {
        return TextDocumentSourceKitOptionsResponse(compilerArguments: [request.textDocument.uri.pseudoPath])
      }

      func prepareTarget(_ request: BuildTargetPrepareRequest) async throws -> BuildTargetPrepareResponse {
        preparationStarted.fulfill()
        await assertThrowsError(try await Task.sleep(for: .seconds(defaultTimeout))) { error in
          XCTAssert(error is CancellationError)
        }
        preparationFinished.fulfill()
        return BuildTargetPrepareResponse()
      }
    }

    let preparationFinished: XCTestExpectation
    do {
      let project = try await CustomBuildServerTestProject(
        files: [
          "Test.swift": """
          func 1️⃣myTestFunc() {}
          """
        ],
        buildServer: BuildServer.self,
        enableBackgroundIndexing: true,
        pollIndex: false
      )
      try await fulfillmentOfOrThrow(project.buildServer().preparationStarted)
      preparationFinished = try project.buildServer().preparationFinished
    }
    try await fulfillmentOfOrThrow(preparationFinished)
  }

  func testBuildServerFailsToInitialize() async throws {
    actor BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()

      init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {}

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        throw ResponseError.unknown("Initialization failed with bad error")
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        throw ResponseError.unknown("Not expected to get called")
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        throw ResponseError.unknown("Not expected to get called")
      }
    }

    let project = try await CustomBuildServerTestProject(
      files: [
        "Test.swift": """
        func 1️⃣myTestFunc() {}
        """
      ],
      buildServer: BuildServer.self
    )
    let message = try await project.testClient.nextNotification(ofType: ShowMessageNotification.self)
    assertContains(message.message, "Initialization failed with bad error")
  }

  func testBuildServerTakesLongToReply() async throws {
    actor BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      let projectRoot: URL
      let unlockBuildServerResponses = MultiEntrySemaphore(name: "Build server starts responding")
      var didReceiveTargetSourcesRequest = false
      var didReceiveBuildTargetsRequest = false

      init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
        self.projectRoot = projectRoot
      }

      func workspaceBuildTargetsRequest(
        _ request: WorkspaceBuildTargetsRequest
      ) async throws -> WorkspaceBuildTargetsResponse {
        // We should cache the result of the request once we receive it and not re-request information after the build
        // server request timeout has fired
        XCTAssert(!didReceiveBuildTargetsRequest)
        didReceiveBuildTargetsRequest = true

        await unlockBuildServerResponses.waitOrXCTFail()

        return WorkspaceBuildTargetsResponse(targets: [
          BuildTarget(
            id: .dummy,
            capabilities: BuildTargetCapabilities(),
            languageIds: [],
            dependencies: []
          )
        ])
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        // We should cache the result of the request once we receive it and not re-request information after the build
        // server request timeout has fired
        XCTAssert(!didReceiveTargetSourcesRequest)
        didReceiveTargetSourcesRequest = true

        await unlockBuildServerResponses.waitOrXCTFail()
        return dummyTargetSourcesResponse(files: [DocumentURI(projectRoot.appending(component: "Test.swift"))])
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        var arguments = [request.textDocument.uri.pseudoPath, "-DFOO"]
        if let defaultSDKPath {
          arguments += ["-sdk", defaultSDKPath]
        }
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
      }
    }

    var options = try await SourceKitLSPOptions.testDefault()
    options.buildServerWorkspaceRequestsTimeout = 0.1 /* seconds */

    let project = try await CustomBuildServerTestProject(
      files: [
        "Test.swift": """
        #if FOO
        func foo() {}
        #endif

        func test() {
          1️⃣foo()
        }
        """
      ],
      buildServer: BuildServer.self,
      options: options
    )

    // Check that we can open a document using fallback settings even if the build server is unresponsive.
    let (uri, positions) = try project.openDocument("Test.swift")
    let definitionWithoutBuildServer = try await project.testClient.send(
      DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    XCTAssertEqual(definitionWithoutBuildServer?.locations, nil)
    try project.buildServer().unlockBuildServerResponses.signal()

    // Once the build server starts being responsive, we should be able to get actual results.
    try await repeatUntilExpectedResult {
      let definitionsWithBuildServer = try await project.testClient.send(
        DefinitionRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
      )
      return definitionsWithBuildServer?.locations?.count == 1
    }
  }

  func testBuildServerTakesLongToInitialize() async throws {
    actor BuildServer: CustomBuildServer {
      let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
      let projectRoot: URL
      let unlockInitializeResponses = MultiEntrySemaphore(name: "Build server starts responding")

      init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
        self.projectRoot = projectRoot
      }

      func initializeBuildRequest(_ request: InitializeBuildRequest) async throws -> InitializeBuildResponse {
        await unlockInitializeResponses.waitOrXCTFail()
        return initializationResponse()
      }

      func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) async throws -> BuildTargetSourcesResponse {
        return dummyTargetSourcesResponse(files: [DocumentURI(projectRoot.appending(component: "Test.swift"))])
      }

      func textDocumentSourceKitOptionsRequest(
        _ request: TextDocumentSourceKitOptionsRequest
      ) async throws -> TextDocumentSourceKitOptionsResponse? {
        var arguments = [request.textDocument.uri.pseudoPath]
        if let defaultSDKPath {
          arguments += ["-sdk", defaultSDKPath]
        }
        return TextDocumentSourceKitOptionsResponse(compilerArguments: arguments)
      }
    }

    var options = try await SourceKitLSPOptions.testDefault()
    options.buildServerWorkspaceRequestsTimeout = 0.1 /* seconds */

    let project = try await CustomBuildServerTestProject(
      files: [
        "Test.swift": """
        func foo() {}
        """
      ],
      buildServer: BuildServer.self,
      options: options,
      pollIndex: false
    )

    let (uri, _) = try project.openDocument("Test.swift")
    _ = try await project.testClient.send(DocumentSymbolRequest(textDocument: TextDocumentIdentifier(uri)))

    try project.buildServer().unlockInitializeResponses.signal()
  }
}
