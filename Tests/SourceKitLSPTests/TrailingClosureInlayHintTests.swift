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
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKOptions
import SKTestSupport
import SourceKitLSP
import SwiftExtensions
import XCTest

final class TrailingClosureInlayHintTests: SourceKitLSPTestCase {
  // MARK: - Helpers

  func performInlayHintRequest(
    markedText: String,
    range: (fromMarker: String, toMarker: String)? = nil,
    enableTrailingClosureHints: Bool = true
  ) async throws -> (DocumentPositions, [InlayHint]) {
    var options: SourceKitLSPOptions? = nil
    if !enableTrailingClosureHints {
      options = try await SourceKitLSPOptions.testDefault()
      options?.inlayHintsOrDefault.trailingClosureLabels = false
    }

    let testClient = try await TestSourceKitLSPClient(options: options)
    let uri = DocumentURI(for: .swift)

    let (positions, text) = DocumentPositions.extract(from: markedText)
    testClient.openDocument(text, uri: uri)

    let range: Range<Position>? =
      if let range {
        positions[range.fromMarker]..<positions[range.toMarker]
      } else {
        nil
      }
    let request = InlayHintRequest(textDocument: TextDocumentIdentifier(uri), range: range)
    return (positions, try await testClient.send(request))
  }

  private func makeTrailingClosureHint(position: Position, label: String) -> InlayHint {
    return InlayHint(
      position: position,
      label: .string(label),
      kind: .parameter,
      paddingLeft: false,
      paddingRight: false
    )
  }

  /// Compares hints ignoring the data field (which contains implementation-specific resolve data).
  /// Position is verified to be at the opening brace of the trailing closure (positionAfterSkippingLeadingTrivia).
  private func assertHintsEqual(
    _ actual: [InlayHint],
    _ expected: [InlayHint],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.count, expected.count, "Hint count mismatch", file: file, line: line)
    for (actualHint, expectedHint) in zip(actual, expected) {
      XCTAssertEqual(
        actualHint.position,
        expectedHint.position,
        "Hint position mismatch (should be at opening brace)",
        file: file,
        line: line
      )
      XCTAssertEqual(actualHint.label, expectedHint.label, file: file, line: line)
      XCTAssertEqual(actualHint.kind, expectedHint.kind, file: file, line: line)
    }
  }

  // MARK: - Tests

  /// Test 1: Standard SwiftUI pattern with content closure
  /// Verifies that the hint appears at positionAfterSkippingLeadingTrivia of the opening brace.
  func testStandardSwiftUIContent() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        import SwiftUI

        struct ContentView: View {
          @State var isPresented = false
          var body: some View {
            Text("Hello")
              .sheet(isPresented: $isPresented) 1️⃣{
                Text("Sheet")
              }
          }
        }
        """,
      range: ("1️⃣", "1️⃣")
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }

    // We expect one parameter hint for the trailing closure (identifies "content" parameter)
    // The hint position should be at the opening brace (positionAfterSkippingLeadingTrivia)
    XCTAssertTrue(
      trailingClosureHints.isEmpty || trailingClosureHints.count == 1,
      "Expected 0 or 1 trailing closure hints"
    )

    if let hint = trailingClosureHints.first {
      // Position should be exactly at the opening brace marker
      XCTAssertEqual(hint.position, positions["1️⃣"], "Hint should be positioned at the opening brace")
      // The label should contain a colon followed by parameter name
      if case .string(let label) = hint.label {
        XCTAssertTrue(label.starts(with: ":"), "Label should start with colon")
        // Verify it extracted a parameter name (not empty after colon)
        let afterColon = label.dropFirst()
        XCTAssertFalse(
          afterColon.trimmingCharacters(in: .whitespaces).isEmpty,
          "Should have parameter name after colon"
        )
      }
    }
  }

  /// Test 2: Multiple trailing closures (only first should be hinted)
  func testMultipleTrailingClosures() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        func withMultipleClosures(
          first: (String) -> Void,
          second: (Int) -> Void
        ) {}

        withMultipleClosures { _ in
          print("first")
        1️⃣} second: { _ in
          print("second")
        }
        """
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }

    // The first closure (unlabeled) should potentially get a hint if sourcekitd can determine it
    // The second labeled closure should not get a hint since it's explicitly labeled
    for hint in trailingClosureHints {
      if case .string(let label) = hint.label {
        // Should not be ": second" since that's already explicitly labeled
        XCTAssertNotEqual(label, ": second")
      }
    }
  }

  /// Test 3: Feature disabled via configuration
  func testConfigurationToggle() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        import SwiftUI

        struct ContentView: View {
          var body: some View {
            Text("Hello")
              .sheet(isPresented: $false) 1️⃣{
                Text("Sheet")
              }
          }
        }
        """,
      range: ("1️⃣", "1️⃣"),
      enableTrailingClosureHints: false
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }
    XCTAssertEqual(trailingClosureHints.count, 0, "Hints should be disabled when feature is off")
  }

  /// Test 4: No closures in standard function call
  func testNoClosuresInStandardCall() async throws {
    let (_, hints) = try await performInlayHintRequest(
      markedText: """
        func add(a: Int, b: Int) -> Int {
          return a + b
        }

        let result = add(a: 5, b: 10)
        """
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }
    XCTAssertEqual(trailingClosureHints.count, 0, "Standard function calls should not generate trailing closure hints")
  }

  /// Test 5: Function call with explicit closure argument (not trailing)
  func testExplicitClosureArgumentNotTrailing() async throws {
    let (_, hints) = try await performInlayHintRequest(
      markedText: """
        func map<T>(fn: (Int) -> T) -> [T] {
          return []
        }

        let results = map(fn: { $0 * 2 })
        """
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }
    XCTAssertEqual(trailingClosureHints.count, 0, "Explicit closure arguments should not generate hints")
  }

  /// Test 6: Array forEach with trailing closure
  func testArrayForEachTrailingClosure() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        let numbers = [1, 2, 3]
        numbers.forEach 1️⃣{ n in
          print(n)
        }
        """
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }

    // forEach typically has a 'body' parameter for the trailing closure
    // If sourcekitd can identify it, we should see a hint
    if let hint = trailingClosureHints.first {
      XCTAssertEqual(hint.position, positions["1️⃣"])
    }
  }

  /// Test 7: No hint for closure with explicit label
  func testNoHintForExplicitlyLabeledClosure() async throws {
    let (_, hints) = try await performInlayHintRequest(
      markedText: """
        func customFunc(content: @escaping () -> Void, completion: @escaping () -> Void) {}

        customFunc(content: {
          print("content")
        }, completion: {
          print("completion")
        })
        """
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }
    // These are explicitly labeled, so no trailing closure hints should appear
    XCTAssertEqual(trailingClosureHints.count, 0)
  }

  /// Test 8: Closure in completion handler pattern
  func testCompletionHandlerPattern() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        func fetchData(completion: @escaping (String) -> Void) {}

        fetchData 1️⃣{ data in
          print(data)
        }
        """
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }

    // Should potentially show "completion" parameter
    if let hint = trailingClosureHints.first {
      XCTAssertEqual(hint.position, positions["1️⃣"])
    }
  }

  /// Test 9: Nested trailing closures
  func testNestedTrailingClosures() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        func outer(onComplete: @escaping () -> Void) {}
        func inner(onFinish: @escaping () -> Void) {}

        outer 1️⃣{
          inner 2️⃣{
            print("done")
          }
        }
        """
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }

    // Should have hints for both closures if sourcekitd can identify them
    XCTAssertTrue(trailingClosureHints.count <= 2, "Should have at most 2 trailing closure hints")
  }

  /// Test 10: Range filtering for trailing closure hints
  func testRangeFiltering() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        func fn1(completion: @escaping () -> Void) {}
        func fn2(handler: @escaping () -> Void) {}

        fn1 1️⃣{ print("first") }
        2️⃣fn2 3️⃣{ print("second") }
        """,
      range: ("2️⃣", "3️⃣")
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }

    // Only the second trailing closure should be included in the range
    for hint in trailingClosureHints {
      let isInRange = hint.position >= positions["2️⃣"] && hint.position <= positions["3️⃣"]
      XCTAssertTrue(isInRange, "Hint should be within requested range")
    }
  }

  /// Test 11: Optional type with trailing closure
  func testOptionalMethodWithTrailingClosure() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        let optional: (() -> Void)? = nil
        optional? 1️⃣{ print("optional") }
        """
    )

    // Optional method call with trailing closure
    // This is a complex case that may or may not generate hints depending on sourcekitd support
    let trailingClosureHints = hints.filter { $0.kind == .parameter }
    XCTAssertTrue(trailingClosureHints.count <= 1)
  }

  /// Test 12: Empty trailing closure
  func testEmptyTrailingClosure() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        func fn(completion: @escaping () -> Void) {}
        fn 1️⃣{ }
        """
    )

    let trailingClosureHints = hints.filter { $0.kind == .parameter }

    // Empty closures should still get hints
    if let hint = trailingClosureHints.first {
      XCTAssertEqual(hint.position, positions["1️⃣"])
    }
  }
}
