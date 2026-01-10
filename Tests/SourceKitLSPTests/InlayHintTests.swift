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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import XCTest

final class InlayHintTests: SourceKitLSPTestCase {
  // MARK: - Helpers

  func performInlayHintRequest(
    markedText: String,
    range: (fromMarker: String, toMarker: String)? = nil
  ) async throws -> (DocumentPositions, [InlayHint]) {
    let testClient = try await TestSourceKitLSPClient()
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

  private func makeInlayHint(
    position: Position,
    kind: InlayHintKind,
    label: String,
    hasEdit: Bool = true
  ) -> InlayHint {
    let textEdits: [TextEdit]?
    if hasEdit {
      textEdits = [TextEdit(range: position..<position, newText: label)]
    } else {
      textEdits = nil
    }
    return InlayHint(
      position: position,
      label: .string(label),
      kind: kind,
      textEdits: textEdits
    )
  }

  /// compares hints ignoring the data field (which contains implementation-specific resolve data)
  private func assertHintsEqual(
    _ actual: [InlayHint],
    _ expected: [InlayHint],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.count, expected.count, "Hint count mismatch", file: file, line: line)
    for (actualHint, expectedHint) in zip(actual, expected) {
      XCTAssertEqual(actualHint.position, expectedHint.position, file: file, line: line)
      XCTAssertEqual(actualHint.label, expectedHint.label, file: file, line: line)
      XCTAssertEqual(actualHint.kind, expectedHint.kind, file: file, line: line)
      XCTAssertEqual(actualHint.textEdits, expectedHint.textEdits, file: file, line: line)
      XCTAssertEqual(actualHint.tooltip, expectedHint.tooltip, file: file, line: line)
    }
  }

  // MARK: - Tests

  func testEmpty() async throws {
    let (_, hints) = try await performInlayHintRequest(markedText: "")
    XCTAssertEqual(hints, [])
  }

  func testBindings() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        let x1️⃣ = 4
        var y2️⃣ = "test" + "123"
        """
    )
    assertHintsEqual(
      hints,
      [
        makeInlayHint(
          position: positions["1️⃣"],
          kind: .type,
          label: ": Int"
        ),
        makeInlayHint(
          position: positions["2️⃣"],
          kind: .type,
          label: ": String"
        ),
      ]
    )
  }

  func testRanged() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        func square(_ x: Double) -> Double {
          let result = x * x
          return result
        }

        func collatz(_ n: Int) -> Int {
        1️⃣  let even2️⃣ = n % 2 == 0
          let result3️⃣ = even ? (n / 2) : (3 * n + 1)
          return result
        } 4️⃣
        """,
      range: ("1️⃣", "4️⃣")
    )
    assertHintsEqual(
      hints,
      [
        makeInlayHint(
          position: positions["2️⃣"],
          kind: .type,
          label: ": Bool"
        ),
        makeInlayHint(
          position: positions["3️⃣"],
          kind: .type,
          label: ": Int"
        ),
      ]
    )
  }

  func testFields() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        class X {
          let instanceMember1️⃣ = 3
          static let staticMember2️⃣ = "abc"
        }

        struct Y {
          var instanceMember3️⃣ = "def" + "ghi"
          static let staticMember4️⃣ = 1 + 2
        }

        enum Z {
          static let staticMember5️⃣ = 3.0
        }
        """
    )
    assertHintsEqual(
      hints,
      [
        makeInlayHint(
          position: positions["1️⃣"],
          kind: .type,
          label: ": Int"
        ),
        makeInlayHint(
          position: positions["2️⃣"],
          kind: .type,
          label: ": String"
        ),
        makeInlayHint(
          position: positions["3️⃣"],
          kind: .type,
          label: ": String"
        ),
        makeInlayHint(
          position: positions["4️⃣"],
          kind: .type,
          label: ": Int"
        ),
        makeInlayHint(
          position: positions["5️⃣"],
          kind: .type,
          label: ": Double"
        ),
      ]
    )
  }

  func testExplicitTypeAnnotation() async throws {
    let (_, hints) = try await performInlayHintRequest(
      markedText: """
        let x: String = "abc"

        struct X {
          var y: Int = 34
        }
        """
    )
    XCTAssertEqual(hints, [])
  }

  func testClosureParams() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        func f(x: Int) {}

        let g1️⃣ = { (x: Int) in }
        let h: (String) -> String = { x2️⃣ in x }
        let i: (Double, Double) -> Double = { (x3️⃣, y4️⃣) in
          x + y
        }
        """
    )
    assertHintsEqual(
      hints,
      [
        makeInlayHint(
          position: positions["1️⃣"],
          kind: .type,
          label: ": (Int) -> ()"
        ),
        makeInlayHint(
          position: positions["2️⃣"],
          kind: .type,
          label: ": String",
          hasEdit: false
        ),
        makeInlayHint(
          position: positions["3️⃣"],
          kind: .type,
          label: ": Double"
        ),
        makeInlayHint(
          position: positions["4️⃣"],
          kind: .type,
          label: ": Double"
        ),
      ]
    )
  }

  func testIfConfigHints() async throws {
    let (positions, hints) = try await performInlayHintRequest(
      markedText: """
        #if DEBUG
        #endif1️⃣
        """
    )
    XCTAssertEqual(
      hints,
      [
        InlayHint(
          position: positions["1️⃣"],
          label: " // DEBUG",
          kind: .type,
          textEdits: [TextEdit(range: Range(positions["1️⃣"]), newText: " // DEBUG")],
          tooltip: .string("Condition of this conditional compilation clause")
        )
      ]
    )
  }

  func testIfConfigHintDoesNotShowIfCommentExits() async throws {
    let (_, hints) = try await performInlayHintRequest(
      markedText: """
        #if DEBUG
        #endif // DEBUG
        """
    )
    XCTAssertEqual(hints, [])
  }

  func testIfConfigHintDoesNotShowIfElseClauseExists() async throws {
    let (_, hints) = try await performInlayHintRequest(
      markedText: """
        #if DEBUG
        #else
        #endif
        """
    )
    XCTAssertEqual(hints, [])
  }

  func testInlayHintResolve() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      struct 1️⃣MyType {}
      let x2️⃣ = MyType()
      """,
      uri: uri
    )

    let request = InlayHintRequest(textDocument: TextDocumentIdentifier(uri), range: nil)
    let hints = try await testClient.send(request)

    guard let typeHint = hints.first(where: { $0.kind == .type }) else {
      XCTFail("Expected type hint")
      return
    }

    XCTAssertNotNil(typeHint.data, "Expected type hint to have data for resolution")

    let resolvedHint = try await testClient.send(InlayHintResolveRequest(inlayHint: typeHint))

    guard case .parts(let parts) = resolvedHint.label else {
      XCTFail("Expected resolved hint to have label parts, got: \(resolvedHint.label)")
      return
    }

    XCTAssertEqual(parts.count, 1, "Expected exactly one label part")

    guard let location = parts.first?.location else {
      XCTFail("Expected label part to have location for go-to-definition")
      return
    }

    XCTAssertEqual(location.uri, uri)
    XCTAssertEqual(location.range.lowerBound, positions["1️⃣"])
  }

  func testInlayHintResolveSDKType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    testClient.openDocument(
      """
      let x = "hello"
      """,
      uri: uri
    )

    let request = InlayHintRequest(textDocument: TextDocumentIdentifier(uri), range: nil)
    let hints = try await testClient.send(request)

    guard let typeHint = hints.first(where: { $0.kind == .type }) else {
      XCTFail("Expected type hint for String")
      return
    }

    // Resolve should not crash, and returns the hint (possibly without location for SDK types in test env)
    let resolvedHint = try await testClient.send(InlayHintResolveRequest(inlayHint: typeHint))
    XCTAssertEqual(resolvedHint.kind, .type)
  }
}
