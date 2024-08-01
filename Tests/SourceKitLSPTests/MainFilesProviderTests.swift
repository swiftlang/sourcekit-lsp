//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKTestSupport
import SourceKitLSP
import XCTest

final class MainFilesProviderTests: XCTestCase {
  func testMainFileForHeaderInPackageTarget() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/include/MyLibrary.h": """
        void bridging(void) {
          int VARIABLE_NAME = 1;
        }
        """,
        "MyLibrary/MyLibrary.c": """
        #include "shared.h"
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(
              name: "MyLibrary",
              cSettings: [.define("VARIABLE_NAME", to: "fromMyLibrary"), .unsafeFlags(["-Wunused-variable"])]
            )
          ]
        )
        """,
      usePullDiagnostics: false
    )

    // Use the definition of `VARIABLE_NAME` together with `-Wunused-variable` to check that we are getting compiler
    // arguments from the target.
    _ = try project.openDocument("MyLibrary.h", language: .c)
    let diags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 1)
    let diag = try XCTUnwrap(diags.diagnostics.first)
    XCTAssertEqual(diag.message, "Unused variable 'fromMyLibrary'")
  }

  func testMainFileForHeaderOutsideOfTarget() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Sources/shared.h": """
        void bridging(void) {
          int VARIABLE_NAME = 1;
        }
        """,
        "Sources/MyLibrary/include/dummy.h": "",
        "Sources/MyLibrary/MyLibrary.c": """
        #include "$TEST_DIR/Sources/shared.h"
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(
              name: "MyLibrary",
              cSettings: [.define("VARIABLE_NAME", to: "fromMyLibrary"), .unsafeFlags(["-Wunused-variable"])]
            )
          ]
        )
        """,
      usePullDiagnostics: false
    )

    _ = try project.openDocument("shared.h", language: .c)

    // Before we build, we shouldn't have an index and thus we don't infer the build setting for 'shared.h' form
    // 'MyLibrary.c'. Hence, we don't have the '-Wunused-variable' build setting and thus no diagnostics.
    let preBuildDiags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(preBuildDiags.diagnostics.count, 0)

    try await SwiftPMTestProject.build(at: project.scratchDirectory)

    // After building we know that 'shared.h' is included from 'MyLibrary.c' and thus we use its build settings,
    // defining `VARIABLE_NAME` to `fromMyLibrary`.
    let postBuildDiags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(postBuildDiags.diagnostics.count, 1)
    let diag = try XCTUnwrap(postBuildDiags.diagnostics.first)
    XCTAssertEqual(diag.message, "Unused variable 'fromMyLibrary'")
  }

  func testMainFileForSharedHeaderOutsideOfTarget() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Sources/shared.h": """
        void bridging(void) {
          int VARIABLE_NAME = 1;
        }
        """,
        "Sources/MyLibrary/include/dummy.h": "",
        "Sources/MyLibrary/MyLibrary.c": """
        #include "$TEST_DIR/Sources/shared.h"
        """,
        "Sources/MyFancyLibrary/include/dummy.h": "",
        "Sources/MyFancyLibrary/MyFancyLibrary.c": """
        #include "$TEST_DIR/Sources/shared.h"
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(
              name: "MyLibrary",
              cSettings: [.define("VARIABLE_NAME", to: "fromMyLibrary"), .unsafeFlags(["-Wunused-variable"])]
            ),
            .target(
              name: "MyFancyLibrary",
              cSettings: [.define("VARIABLE_NAME", to: "fromMyFancyLibrary"), .unsafeFlags(["-Wunused-variable"])]
            )
          ]
        )
        """,
      enableBackgroundIndexing: true,
      usePullDiagnostics: false
    )

    _ = try project.openDocument("shared.h", language: .c)

    // We could pick build settings from either 'MyLibrary.c' or 'MyFancyLibrary.c'. We currently pick the
    // lexicographically first to be deterministic, which is 'MyFancyLibrary'. Thus `VARIABLE_NAME` is set to
    // `fromMyFancyLibrary`.
    let diags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(diags.diagnostics.count, 1)
    let diag = try XCTUnwrap(diags.diagnostics.first)
    XCTAssertEqual(diag.message, "Unused variable 'fromMyFancyLibrary'")
  }

  func testMainFileChangesIfIncludeIsAdded() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Sources/shared.h": """
        void bridging(void) {
          int VARIABLE_NAME = 1;
        }
        """,
        "Sources/MyLibrary/include/dummy.h": "",
        "Sources/MyLibrary/MyLibrary.c": """
        #include "$TEST_DIR/Sources/shared.h"
        """,
        "Sources/MyFancyLibrary/include/dummy.h": "",
        "Sources/MyFancyLibrary/MyFancyLibrary.c": "",
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
            .target(
              name: "MyLibrary",
              cSettings: [.define("VARIABLE_NAME", to: "fromMyLibrary"), .unsafeFlags(["-Wunused-variable"])]
            ),
            .target(
              name: "MyFancyLibrary",
              cSettings: [.define("VARIABLE_NAME", to: "fromMyFancyLibrary"), .unsafeFlags(["-Wunused-variable"])]
            )
          ]
        )
        """,
      enableBackgroundIndexing: true,
      usePullDiagnostics: false
    )

    _ = try project.openDocument("shared.h", language: .c)

    // 'MyLibrary.c' is the only file that includes 'shared.h' at first. So we use build settings from MyLibrary and
    // define `VARIABLE_NAME` to `fromMyLibrary`.
    let preEditDiags = try await project.testClient.nextDiagnosticsNotification()
    XCTAssertEqual(preEditDiags.diagnostics.count, 1)
    let preEditDiag = try XCTUnwrap(preEditDiags.diagnostics.first)
    XCTAssertEqual(preEditDiag.message, "Unused variable 'fromMyLibrary'")

    let newFancyLibraryContents = """
      #include "\(project.scratchDirectory.path)/Sources/shared.h"
      """
    let fancyLibraryUri = try project.uri(for: "MyFancyLibrary.c")
    try newFancyLibraryContents.write(to: try XCTUnwrap(fancyLibraryUri.fileURL), atomically: false, encoding: .utf8)
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: fancyLibraryUri, type: .changed)])
    )

    // 'MyFancyLibrary.c' now also includes 'shared.h'. Since it lexicographically preceeds MyLibrary, we should use its
    // build settings.
    // `clangd` may return diagnostics from the old build settings sometimes (I believe when it's still building the
    // preamble for shared.h when the new build settings come in). Check that it eventually returns the correct
    // diagnostics.
    try await repeatUntilExpectedResult {
      let refreshedDiags = try await project.testClient.nextDiagnosticsNotification(timeout: .seconds(1))
      guard let diagnostic = refreshedDiags.diagnostics.only else {
        return false
      }
      return diagnostic.message == "Unused variable 'fromMyFancyLibrary'"
    }
  }
}
