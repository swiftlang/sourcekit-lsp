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

import LanguageServerProtocol
import SKTestSupport
import XCTest

final class DependencyTrackingTests: XCTestCase {
  func testDependenciesUpdatedSwift() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/LibA.swift": """
        public func aaa() {}
        """,
        "LibB/LibB.swift": """
        import LibA
        public func bbb() {
          aaa()
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [
           .target(name: "LibA"),
           .target(name: "LibB", dependencies: ["LibA"]),
          ]
        )
        """,
      usePullDiagnostics: false
    )

    let (libBUri, _) = try project.openDocument("LibB.swift")

    let initialDiags = try await project.testClient.nextDiagnosticsNotification()
    // Semantic analysis: expect module import error.
    XCTAssertEqual(initialDiags.diagnostics.count, 1)
    if let diagnostic = initialDiags.diagnostics.first {
      #if compiler(>=6.1)
      #warning("When we drop support for Swift 5.10 we no longer need to check for the Objective-C error message")
      #endif
      XCTAssert(
        diagnostic.message.contains("Could not build Objective-C module")
          || diagnostic.message.contains("No such module"),
        "expected module import error but found \"\(diagnostic.message)\""
      )
    }

    try await SwiftPMTestProject.build(at: project.scratchDirectory)

    await project.testClient.server.filesDependenciesUpdated([libBUri])

    let updatedDiags = try await project.testClient.nextDiagnosticsNotification()
    // Semantic analysis: no more errors expected, import should resolve since we built.
    XCTAssertEqual(updatedDiags.diagnostics.count, 0)
  }

  func testDependenciesUpdatedCXX() async throws {
    let project = try await MultiFileTestProject(
      files: [
        "lib.c": """
        int libX(int value) {
          return value ? 22 : 0;
        }
        """,
        "main.c": """
        #include "lib-generated.h"

        int main(int argc, const char *argv[]) {
          return libX(argc);
        }
        """,
        "compile_flags.txt": "",
      ],
      usePullDiagnostics: false
    )

    let generatedHeaderURL = try project.uri(for: "main.c").fileURL!.deletingLastPathComponent()
      .appendingPathComponent("lib-generated.h", isDirectory: false)

    // Write an empty header file first since clangd doesn't handle missing header
    // files without a recently upstreamed extension.
    try "".write(to: generatedHeaderURL, atomically: true, encoding: .utf8)
    let (mainUri, _) = try project.openDocument("main.c")

    let openDiags = try await project.testClient.nextDiagnosticsNotification()
    // Expect one error:
    // - Implicit declaration of function invalid
    XCTAssertEqual(openDiags.diagnostics.count, 1)

    // Update the header file to have the proper contents for our code to build.
    let contents = "int libX(int value);"
    try contents.write(to: generatedHeaderURL, atomically: true, encoding: .utf8)

    await project.testClient.server.filesDependenciesUpdated([mainUri])

    let updatedDiags = try await project.testClient.nextDiagnosticsNotification()
    // No more errors expected, import should resolve since we the generated header file
    // now has the proper contents.
    XCTAssertEqual(updatedDiags.diagnostics.count, 0)
  }
}
