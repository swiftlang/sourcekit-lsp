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

let sdkArgs =
  if let defaultSDKPath {
    """
    "-sdk", "\(defaultSDKPath)",
    """
  } else {
    ""
  }

final class LegacyBuildServerBuildSystemIntegrationTests: XCTestCase {
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
          def register_for_changes(self, notification: Dict[str, object]):
            if notification["action"] == "register":
              self.send_notification(
                "build/sourceKitOptionsChanged",
                {
                  "uri": notification["uri"],
                  "updatedOptions": {
                    "options": [
                      "$TEST_DIR/Test.swift",
                      "-DDEBUG",
                      \(sdkArgs)
                    ]
                  },
                },
              )
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

  func testBuildSettingsFromBuildServerChanged() async throws {
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
          def send_delayed_options_changed(self, uri: str):
            self.send_sourcekit_options_changed(uri, ["$TEST_DIR/Test.swift", "-DDEBUG", \(sdkArgs)])

          def register_for_changes(self, notification: Dict[str, object]):
            if notification["action"] != "register":
              return
            self.send_sourcekit_options_changed(
              notification["uri"],
              ["$TEST_DIR/Test.swift", \(sdkArgs)]
            )
            threading.Timer(1, self.send_delayed_options_changed, [notification["uri"]]).start()
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
}
