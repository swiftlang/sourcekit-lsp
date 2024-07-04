//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LSPTestSupport
import LanguageServerProtocol
import SKTestSupport
import XCTest

final class CodeLensTests: XCTestCase {
  func testNoLenses() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        struct MyApp {
          public static func main() {}
        }
        """
      ]
    )
    let (uri, _) = try project.openDocument("Test.swift")

    let response = try await project.testClient.send(
      CodeLensRequest(textDocument: TextDocumentIdentifier(uri))
    )

    XCTAssertEqual(response, [])
  }

  func testSuccessfulCodeLensRequest() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": """
        1️⃣@main2️⃣
        struct MyApp {
          public static func main() {}
        }
        """
      ]
    )

    let (uri, positions) = try project.openDocument("Test.swift")

    let response = try await project.testClient.send(
      CodeLensRequest(textDocument: TextDocumentIdentifier(uri))
    )

    XCTAssertEqual(
      response,
      [
        CodeLens(
          range: positions["1️⃣"]..<positions["2️⃣"],
          command: Command(title: "Run", command: "swift.run", arguments: nil)
        ),
        CodeLens(
          range: positions["1️⃣"]..<positions["2️⃣"],
          command: Command(title: "Debug", command: "swift.debug", arguments: nil)
        ),
      ]
    )
  }
}
