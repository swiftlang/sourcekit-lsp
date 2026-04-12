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
import SwiftExtensions
import XCTest

final class InlayHintTests: SourceKitLSPTestCase {
  // MARK: - Helpers
  class InlayHintTestCaseContext {
    let positions: DocumentPositions
    let testClient: TestSourceKitLSPClient
    let uri: DocumentURI
    private let range: Range<Position>?
    private let testCase: XCTestCase
    private var version: Int = 1

    init(
      positions: DocumentPositions,
      testClient: TestSourceKitLSPClient,
      uri: DocumentURI,
      range: Range<Position>?,
      testCase: XCTestCase
    ) {
      self.positions = positions
      self.testClient = testClient
      self.uri = uri
      self.range = range
      self.testCase = testCase
    }

    func getBackgroundComputedInlayHints() async throws -> [InlayHint] {
      let refreshRequestReceived = testCase.expectation(description: "Receive first inlay hint refresh request")
      testClient.handleSingleRequest { (_: InlayHintRefreshRequest) in
        refreshRequestReceived.fulfill()
        return VoidResponse()
      }

      let request = InlayHintRequest(textDocument: TextDocumentIdentifier(uri), range: range)
      let _ = try await testClient.send(request)
      await testCase.fulfillment(of: [refreshRequestReceived], timeout: 10)
      return try await testClient.send(request)
    }

    func getCachedInlayHints() async throws -> [InlayHint] {
      let request = InlayHintRequest(textDocument: TextDocumentIdentifier(uri), range: range)
      return try await testClient.send(request)
    }

    func sendChange(range: Range<Position>, text: String) {
      sendChanges(changes: [(range: range, text: text)])
    }

    func sendChanges(changes: [(range: Range<Position>, text: String)]) {
      testClient.send(
        DidChangeTextDocumentNotification(
          textDocument: VersionedTextDocumentIdentifier(uri, version: version),
          contentChanges: changes.map { change in
            TextDocumentContentChangeEvent(
              range: change.range,
              text: change.text
            )
          }
        )
      )
      version += 1
    }
  }

  private func runInlayHintTestCase(
    initialText: String,
    range: (start: String, end: String)? = nil,
    testBody: (InlayHintTestCaseContext) async throws -> Void
  ) async throws {
    let capabilities = ClientCapabilities(
      workspace: WorkspaceClientCapabilities(inlayHint: RefreshRegistrationCapability(refreshSupport: true))
    )
    let testClient = try await TestSourceKitLSPClient(capabilities: capabilities)
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(initialText, uri: uri)

    let transformedRange = range.map { (start, end) in
      let startPos = positions[start]
      let endPos = positions[end]
      return startPos..<endPos
    }
    let context = InlayHintTestCaseContext(
      positions: positions,
      testClient: testClient,
      uri: uri,
      range: transformedRange,
      testCase: self
    )
    try await testBody(context)
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
    try await runInlayHintTestCase(initialText: "") {
      let hints = try await $0.getBackgroundComputedInlayHints()
      XCTAssertEqual(hints, [])
    }
  }

  func testBindings() async throws {
    try await runInlayHintTestCase(
      initialText: """
        let x1️⃣ = 4
        var y2️⃣ = "test" + "123"
        """
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["1️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: $0.positions["2️⃣"], kind: .type, label: ": String"),
        ]
      )
    }
  }

  func testRangedRangeOverlapsUntilAfterLastHint() async throws {
    try await runInlayHintTestCase(
      initialText: """
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
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["2️⃣"], kind: .type, label: ": Bool"),
          makeInlayHint(position: $0.positions["3️⃣"], kind: .type, label: ": Int"),
        ]
      )
    }
  }

  func testRangedRangeOverlapsUntilBeforeFirstHint() async throws {
    try await runInlayHintTestCase(
      initialText: """
        1️⃣let x2️⃣ = 43️⃣
        var y = "test" + "123"
        """,
      range: ("1️⃣", "3️⃣")
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["2️⃣"], kind: .type, label: ": Int")
        ]
      )
    }
  }

  func testRangedRangeOverlapsAllHints() async throws {
    try await runInlayHintTestCase(
      initialText: """
        let1️⃣ x2️⃣ = 4
        var y3️⃣ = "test" + "123"4️⃣
        """,
      range: ("1️⃣", "4️⃣")
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["2️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: $0.positions["3️⃣"], kind: .type, label: ": String"),
        ]
      )
    }
  }

  func testRangedRangeDoesNotOverlapAnyHints() async throws {
    try await runInlayHintTestCase(
      initialText: """
        let x = 4
        var y = 1️⃣"test" + "123"2️⃣
        """,
      range: ("1️⃣", "2️⃣")
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      XCTAssertEqual(hints, [])
    }
  }

  func testFields() async throws {
    try await runInlayHintTestCase(
      initialText: """
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
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["1️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: $0.positions["2️⃣"], kind: .type, label: ": String"),
          makeInlayHint(position: $0.positions["3️⃣"], kind: .type, label: ": String"),
          makeInlayHint(position: $0.positions["4️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: $0.positions["5️⃣"], kind: .type, label: ": Double"),
        ]
      )
    }
  }

  func testExplicitTypeAnnotation() async throws {
    try await runInlayHintTestCase(
      initialText: """
        let x: String = "abc"

        struct X {
          var y: Int = 34
        }
        """
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      XCTAssertEqual(hints, [])
    }
  }

  func testClosureParams() async throws {
    try await runInlayHintTestCase(
      initialText: """
        func f(x: Int) {}

        let g1️⃣ = { (x: Int) in }
        let h: (String) -> String = { x2️⃣ in x }
        let i: (Double, Double) -> Double = { (x3️⃣, y4️⃣) in
          x + y
        }
        """
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["1️⃣"], kind: .type, label: ": (Int) -> ()"),
          makeInlayHint(position: $0.positions["2️⃣"], kind: .type, label: ": String", hasEdit: false),
          makeInlayHint(position: $0.positions["3️⃣"], kind: .type, label: ": Double"),
          makeInlayHint(position: $0.positions["4️⃣"], kind: .type, label: ": Double"),
        ]
      )
    }
  }

  func testIfConfigHints() async throws {
    try await runInlayHintTestCase(
      initialText: """
        #if DEBUG
        #endif1️⃣
        """
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      XCTAssertEqual(
        hints,
        [
          InlayHint(
            position: $0.positions["1️⃣"],
            label: " // DEBUG",
            kind: .type,
            textEdits: [TextEdit(range: Range($0.positions["1️⃣"]), newText: " // DEBUG")],
            tooltip: .string("Condition of this conditional compilation clause")
          )
        ]
      )
    }
  }

  func testIfConfigHintDoesNotShowIfCommentExits() async throws {
    try await runInlayHintTestCase(
      initialText: """
        #if DEBUG
        #endif // DEBUG
        """
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      XCTAssertEqual(hints, [])
    }
  }

  func testIfConfigHintDoesNotShowIfElseClauseExists() async throws {
    try await runInlayHintTestCase(
      initialText: """
        #if DEBUG
        #else
        #endif
        """
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      XCTAssertEqual(hints, [])
    }
  }

  func testInlayHintResolve() async throws {
    try await runInlayHintTestCase(
      initialText: """
        struct 1️⃣MyType {}
        let x2️⃣ = MyType()
        """,
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()

      guard let typeHint = hints.first(where: { $0.kind == .type }) else {
        XCTFail("Expected type hint")
        return
      }

      XCTAssertNotNil(typeHint.data, "Expected type hint to have data for resolution")

      let resolvedHint = try await $0.testClient.send(InlayHintResolveRequest(inlayHint: typeHint))

      guard case .parts(let parts) = resolvedHint.label else {
        XCTFail("Expected resolved hint to have label parts, got: \(resolvedHint.label)")
        return
      }

      guard let location = parts.only?.location else {
        XCTFail("Expected label part to have location for go-to-definition")
        return
      }

      XCTAssertEqual(location.uri, $0.uri)
      XCTAssertEqual(location.range, Range($0.positions["1️⃣"]))
    }
  }

  func testInlayHintResolveCrossModule() async throws {
    let inlayHintRefreshRequestReceived = expectation(description: "Receive inlay hint refresh request")
    let capabilities = ClientCapabilities(
      workspace: WorkspaceClientCapabilities(
        inlayHint: RefreshRegistrationCapability(refreshSupport: true)
      )
    )
    let project = try await SwiftPMTestProject(
      files: [
        "LibA/MyType.swift": """
        public struct 1️⃣MyType {
          public init() {}
        }
        """,
        "LibB/UseType.swift": """
        import LibA
        let x2️⃣ = MyType()
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
      capabilities: capabilities,
      enableBackgroundIndexing: true,
    )

    project.testClient.handleSingleRequest { (_: InlayHintRefreshRequest) in
      inlayHintRefreshRequestReceived.fulfill()
      return VoidResponse()
    }

    let (uri, _) = try project.openDocument("UseType.swift")

    let request = InlayHintRequest(textDocument: TextDocumentIdentifier(uri), range: nil)
    let _ = try await project.testClient.send(request)
    await fulfillment(of: [inlayHintRefreshRequestReceived], timeout: 10)
    let hints = try await project.testClient.send(request)

    guard let typeHint = hints.first(where: { $0.kind == .type }) else {
      XCTFail("Expected type hint for MyType")
      return
    }

    let resolvedHint = try await project.testClient.send(InlayHintResolveRequest(inlayHint: typeHint))

    guard case .parts(let parts) = resolvedHint.label,
      let location = parts.only?.location
    else {
      XCTFail("Expected label part to have location for go-to-definition")
      return
    }

    // The location should point to LibA/MyType.swift where MyType is defined
    XCTAssertEqual(location.uri, try project.uri(for: "MyType.swift"))
    XCTAssertEqual(location.range, try Range(project.position(of: "1️⃣", in: "MyType.swift")))
  }

  func testInlayHintResolveSDKType() async throws {
    let inlayHintRefreshRequestReceived = expectation(description: "Receive inlay hint refresh request")
    let capabilities = ClientCapabilities(
      workspace: WorkspaceClientCapabilities(
        inlayHint: RefreshRegistrationCapability(refreshSupport: true)
      )
    )
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      let 1️⃣x = "hello"
      """,
      capabilities: capabilities,
      indexSystemModules: true
    )

    project.testClient.handleSingleRequest { (_: InlayHintRefreshRequest) in
      inlayHintRefreshRequestReceived.fulfill()
      return VoidResponse()
    }

    let request = InlayHintRequest(textDocument: TextDocumentIdentifier(project.fileURI), range: nil)
    let _ = try await project.testClient.send(request)
    await fulfillment(of: [inlayHintRefreshRequestReceived], timeout: 10)
    let hints = try await project.testClient.send(request)

    guard let typeHint = hints.first(where: { $0.kind == .type }) else {
      XCTFail("Expected type hint for String")
      return
    }

    let resolvedHint = try await project.testClient.send(InlayHintResolveRequest(inlayHint: typeHint))

    guard case .parts(let parts) = resolvedHint.label,
      let location = parts.only?.location
    else {
      XCTFail("Expected label part to have location for go-to-definition")
      return
    }

    // Should point to generated Swift interface
    XCTAssertTrue(
      location.uri.pseudoPath.hasSuffix(".swiftinterface"),
      "Expected .swiftinterface file, got: \(location.uri.pseudoPath)"
    )
  }

  func testInlayHintWithoutRefreshSupport() async throws {
    let capabilities = ClientCapabilities(workspace: WorkspaceClientCapabilities(inlayHint: nil))
    let testClient = try await TestSourceKitLSPClient(capabilities: capabilities)
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      let x1️⃣ = 4
      """,
      uri: uri
    )

    let request = InlayHintRequest(textDocument: TextDocumentIdentifier(uri))
    let hints = try await testClient.send(request)
    assertHintsEqual(
      hints,
      [
        makeInlayHint(position: positions["1️⃣"], kind: .type, label: ": Int")
      ]
    )
  }

  func testInlayHintCacheUpdatesAfterParameterTypeChange() async throws {
    try await runInlayHintTestCase(
      initialText: """
        func test(x: 1️⃣Int2️⃣) {
          let y3️⃣ = x
        }
        """,
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["3️⃣"], kind: .type, label: ": Int")
        ]
      )

      $0.sendChange(
        range: $0.positions["1️⃣"]..<$0.positions["2️⃣"],
        text: "String"
      )

      let shiftedHints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        shiftedHints,
        [
          makeInlayHint(position: $0.positions["3️⃣"], kind: .type, label: ": String")
        ]
      )
    }
  }

  func testInlayHintShiftingWorks() async throws {
    try await runInlayHintTestCase(
      initialText: """
        let y1️⃣ = 2
        2️⃣
        let x3️⃣ = 4
        """,
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["1️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: $0.positions["3️⃣"], kind: .type, label: ": Int"),
        ]
      )

      $0.sendChange(
        range: $0.positions["2️⃣"]..<$0.positions["2️⃣"],
        text: """
          let a: Int = 5
          let b: Int = 10
          """
      )

      let shiftedHints = try await $0.getCachedInlayHints()
      assertHintsEqual(
        shiftedHints,
        [
          makeInlayHint(position: $0.positions["1️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: Position(line: 3, utf16index: 5), kind: .type, label: ": Int"),
        ]
      )
    }
  }

  func testInlayHintShiftingRemovesHintsInsideDeletedRegion() async throws {
    try await runInlayHintTestCase(
      initialText: """
        let x1️⃣ = 1
        2️⃣let y3️⃣ = 24️⃣
        let z5️⃣ = ""
        """,
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["1️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: $0.positions["3️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: $0.positions["5️⃣"], kind: .type, label: ": String"),
        ]
      )

      $0.sendChange(
        range: $0.positions["2️⃣"]..<$0.positions["4️⃣"],
        text: ""
      )

      let shiftedHints = try await $0.getCachedInlayHints()
      assertHintsEqual(
        shiftedHints,
        [
          makeInlayHint(position: $0.positions["1️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: Position(line: 2, utf16index: 5), kind: .type, label: ": String"),
        ]
      )
    }
  }

  func testInlayHintShiftingWithInsertionDirectlyBeforeAHint() async throws {
    try await runInlayHintTestCase(
      initialText: """
        let x1️⃣ = 1
        """,
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["1️⃣"], kind: .type, label: ": Int")
        ]
      )

      $0.sendChange(
        range: $0.positions["1️⃣"]..<$0.positions["1️⃣"],
        text: "yz"
      )

      let shiftedHints = try await $0.getCachedInlayHints()
      assertHintsEqual(
        shiftedHints,
        [
          makeInlayHint(position: Position(line: 0, utf16index: 7), kind: .type, label: ": Int")
        ]
      )
    }
  }

  func testInlayHintShiftingWithMultipleChanges() async throws {
    try await runInlayHintTestCase(
      initialText: """
        let x1️⃣ = 1
        let y2️⃣ = 2

        let z3️⃣ = ""
        """,
    ) {
      let hints = try await $0.getBackgroundComputedInlayHints()
      assertHintsEqual(
        hints,
        [
          makeInlayHint(position: $0.positions["1️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: $0.positions["2️⃣"], kind: .type, label: ": Int"),
          makeInlayHint(position: $0.positions["3️⃣"], kind: .type, label: ": String"),
        ]
      )

      $0.sendChanges(changes: [
        (range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0), text: "let abc = 5\n"),
        (range: Position(line: 2, utf16index: 0)..<Position(line: 2, utf16index: "let y = 2".count + 1), text: ""),
        (range: Position(line: 3, utf16index: 0)..<Position(line: 3, utf16index: 0), text: "let str = \"test\"\n"),
      ])

      // text after edits:
      // let abc = 5
      // let x = 1
      //
      // let str = "test"
      // let z = ""

      let shiftedHints = try await $0.getCachedInlayHints()
      assertHintsEqual(
        shiftedHints,
        [
          // hint for let x = 1
          makeInlayHint(position: Position(line: 1, utf16index: 5), kind: .type, label: ": Int"),
          // hint for let z = ""
          makeInlayHint(position: Position(line: 4, utf16index: 5), kind: .type, label: ": String"),
          // no other hints are present as they were either removed or haven't been computed by the background task yet
        ]
      )
    }
  }
}
