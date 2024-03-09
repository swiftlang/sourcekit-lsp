//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(Testing) import Diagnose
import Foundation
import LSPLogging
import LSPTestSupport
@_spi(Testing) import SKCore
import SKTestSupport
import SourceKitD
import XCTest

import class ISDBTibs.TibsBuilder
import struct TSCBasic.AbsolutePath

final class DiagnoseTests: XCTestCase {
  /// If a default SDK is present on the test machine, return the `-sdk` argument that can be placed in the request
  /// YAML. Otherwise, return an empty string.
  private var sdkArg: String {
    if let sdk = TibsBuilder.defaultSDKPath {
      return """
        "-sdk", "\(sdk)",
        """
    } else {
      return ""
    }
  }

  func testRemoveCodeItemsAndMembers() async throws {
    // We consider the test case reproducing if cursor info returns the two ambiguous results including their doc
    // comments.
    // We should strip away unrelated declarations and statements.
    try await assertReduce(
      """
      func test() {
        let foo = Foo()
        print("test")
        foo.1️⃣ambiguous()
      }

      struct Foo {
        /// Returns an integer
        func ambiguous() -> Int {
          return 1 + 2
        }

        /// Returns a string
        func ambiguous() -> String {
          // a unrelated comment
          return "abc"
        }

        func unrelated() {}
      }

      struct UnrelatedStruct {}
      """,
      request: """
        {
          key.request: source.request.cursorinfo,
          key.compilerargs: [
            "$FILE",
            \(sdkArg)
          ],
          key.offset: $OFFSET,
          key.sourcefile: "$FILE"
        }
        """,
      reproducerPredicate: { $0.contains("Returns an integer") && $0.contains("Returns a string") },
      expectedReducedFileContents: """
        func test() {
          let foo = Foo()
          foo.ambiguous()
        }

        struct Foo {
          /// Returns an integer
          func ambiguous() -> Int {
          }

          /// Returns a string
          func ambiguous() -> String {
          }
        }
        """
    )
  }

  func testRemoveComments() async throws {
    try await assertReduce(
      """
      /// Doc comment
      func test() {
        // Comment
        let foo = 1️⃣Foo()
      }

      /* 
       Block comment
       With another line
      */
      struct Foo {

      }
      """,
      request: """
        {
          key.request: source.request.cursorinfo,
          key.compilerargs: [
            "$FILE",
            \(sdkArg)
          ],
          key.offset: $OFFSET,
          key.sourcefile: "$FILE"
        }
        """,
      reproducerPredicate: { $0.contains("Foo") },
      expectedReducedFileContents: """
        func test() {
            let foo = Foo()
        }

        struct Foo {

        }
        """
    )
  }
}

/// Check that reducing `request` with the given file contents results in `expectedReducedFileContents`.
///
/// - Parameters:
///   - markedFileContents: The contents of the files that should be reduced. Must contain a 1️⃣ location marker, which
///     will be used to substitute `$OFFSET` in `request`.
///   - request: The YAML sourcekitd request that should be reduced. May contain the following placeholders:
///     - `$FILE`: The path of the input file
///     - `$OFFSET`: The UTF-8 offset of the 1️⃣ location marker in `markedFileContents`
///   - reproducerPredicate: A predicate that indicates whether a run request reproduces the issue.
///   - expectedReducedFileContents: The contents of the file that the reducer is expected to produce.
private func assertReduce(
  _ markedFileContents: String,
  request: String,
  reproducerPredicate: @escaping (String) -> Bool,
  expectedReducedFileContents: String,
  file: StaticString = #file,
  line: UInt = #line
) async throws {
  let (markers, fileContents) = extractMarkers(markedFileContents)

  let sourcekitd = try await unwrap(ToolchainRegistry.forTesting.default?.sourcekitd?.asURL)
  logger.debug("Using \(sourcekitd.path) to reduce source file")
  let requestExecutor = InProcessSourceKitRequestExecutor(
    sourcekitd: sourcekitd,
    reproducerPredicate: NSPredicate(block: { (requestResponse, _) -> Bool in
      reproducerPredicate(requestResponse as! String)
    })
  )

  let markerOffset = try XCTUnwrap(markers["1️⃣"], "Failed to find position marker 1️⃣ in file contents")

  try await withTestScratchDir { scratchDir in
    let testFilePath = scratchDir.appending(component: "test.swift").pathString
    try fileContents.write(toFile: testFilePath, atomically: false, encoding: .utf8)

    let request =
      request
      .replacingOccurrences(of: "$FILE", with: testFilePath)
      .replacingOccurrences(of: "$OFFSET", with: String(markerOffset))

    let requestInfo = try RequestInfo(request: request)
    var lastProgress = 0.0
    let reduced = try await requestInfo.reduceInputFile(
      using: requestExecutor,
      progressUpdate: { progress, _ in
        XCTAssertLessThanOrEqual(lastProgress, progress)
        lastProgress = progress
      }
    )

    XCTAssertEqual(reduced.fileContents, expectedReducedFileContents, file: file, line: line)
  }
}

/// We can't run the `OutOfProcessSourceKitRequestExecutor` in tests because that runs the sourcekit-lsp executable,
/// which isn't built when running tests.
private class InProcessSourceKitRequestExecutor: SourceKitRequestExecutor {
  /// The path to `sourcekitd.framework/sourcekitd`.
  private let sourcekitd: URL

  /// The file to which we write the reduce source file.
  private let temporarySourceFile: URL

  /// The file to which we write the AYML request that we want to run.
  private let temporaryRequestFile: URL

  /// If this predicate evaluates to true on the sourcekitd response, the request is
  /// considered to reproduce the issue.
  private let reproducerPredicate: NSPredicate

  init(sourcekitd: URL, reproducerPredicate: NSPredicate) {
    self.sourcekitd = sourcekitd
    self.reproducerPredicate = reproducerPredicate
    temporaryRequestFile = FileManager.default.temporaryDirectory.appendingPathComponent("request-\(UUID()).yml")
    temporarySourceFile = FileManager.default.temporaryDirectory.appendingPathComponent("recude-\(UUID()).swift")
  }

  deinit {
    try? FileManager.default.removeItem(at: temporaryRequestFile)
    try? FileManager.default.removeItem(at: temporarySourceFile)
  }

  func run(request: RequestInfo) async throws -> SourceKitDRequestResult {
    try request.fileContents.write(to: temporarySourceFile, atomically: true, encoding: .utf8)
    let requestString = try request.request(for: temporarySourceFile)
    logger.info("Sending request: \(requestString)")

    let sourcekitd = try await DynamicallyLoadedSourceKitD.getOrCreate(
      dylibPath: try! AbsolutePath(validating: sourcekitd.path)
    )
    let response = try await sourcekitd.run(requestYaml: requestString)

    logger.info("Received response: \(response.description)")

    switch response.error {
    case .requestFailed, .requestInvalid, .requestCancelled, .missingRequiredSymbol, .connectionInterrupted:
      return .error
    case nil:
      if reproducerPredicate.evaluate(with: response.description) {
        return .reproducesIssue
      }
      return .success(response: response.description)
    }
  }
}
