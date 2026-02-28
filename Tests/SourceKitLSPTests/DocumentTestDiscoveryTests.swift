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

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SourceKitLSP
import XCTest

final class DocumentTestDiscoveryTests: SourceKitLSPTestCase {
  func testIndexBasedDocumentTests() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        1️⃣class MyTests: XCTestCase {
          2️⃣func testMyLibrary() {}3️⃣
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }4️⃣
        """,
        "Tests/MyLibraryTests/MoreTests.swift": """
        import XCTest

        class MoreTests: XCTestCase {
          func testSomeMore() {}
        }
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("MyTests.swift")
    let tests = try await project.testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: Location(uri: try project.uri(for: "MyTests.swift"), range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSyntacticDocumentTestsSwift() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import XCTest

      1️⃣class MyTests: XCTestCase {
        2️⃣func testMyLibrary() {}3️⃣
        func testWithAnArgument(x: Int) {}
        func unrelatedFunc() {}
        var testVariable: Int = 0
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testDocumentTestsGetRefinedWithIndexedFile() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class LooksLikeTestCaseButIsNot {}

        1️⃣class MyTests: LooksLikeTestCaseButIsNot {
          2️⃣func testMyLibrary() {}3️⃣
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }4️⃣
        """
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """
    )

    let (uri, positions) = try project.openDocument("MyTests.swift")

    // Syntactically we can't tell that `LooksLikeTestCaseButIsNot` is not a subclass of `XCTestCase`.
    // We are thus conservative and report it as tests.
    let syntacticTests = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      syntacticTests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )

    try await SwiftPMTestProject.build(at: project.scratchDirectory)
    try await project.testClient.send(SynchronizeRequest(index: true))

    // After indexing, we know that `LooksLikeTestCaseButIsNot` does not inherit from `XCTestCase` and we don't report any tests.
    let indexBasedTests = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(indexBasedTests, [])
  }

  func testSwiftTestingDocumentTests() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingDocumentTestsInIndexedProject() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      allowBuildFailure: true
    )

    let tests = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(project.fileURI))
    )
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: project.fileURI, range: project.positions["1️⃣"]..<project.positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: project.fileURI, range: project.positions["2️⃣"]..<project.positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingNestedSuites() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣struct Inner {
          3️⃣@Test
          func oneIsTwo() {
            #expect(1 == 2)
          }4️⃣
        }5️⃣
      }6️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["6️⃣"]),
          children: [
            TestItem(
              id: "MyTests/Inner",
              label: "Inner",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["5️⃣"]),
              children: [
                TestItem(
                  id: "MyTests/Inner/oneIsTwo()",
                  label: "oneIsTwo()",
                  style: TestStyle.swiftTesting,
                  location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"])
                )
              ]
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingParameterizedTest() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test(arguments: [0, 1, 2])
        func numbersAreOne(x: Int) {
          #expect(x == 1)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/numbersAreOne(x:)",
              label: "numbersAreOne(x:)",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingParameterizedTestWithAnonymousArgument() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test(arguments: [0, 1, 2])
        func numbersAreOne(_ x: Int) {
          #expect(x == 1)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/numbersAreOne(_:)",
              label: "numbersAreOne(_:)",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testSwiftTestingParameterizedTestWithCommentInSignature() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test(arguments: [0, 1, 2])
        func numbersAreOne(x /* hello */: Int) {
          #expect(x == 1)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/numbersAreOne(x:)",
              label: "numbersAreOne(x:)",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestsWithDuplicateFunctionIdentifiers() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Test(arguments: [1, 2, 3])
      func foo(_ x: Int) {}2️⃣
      3️⃣@Test(arguments: ["a", "b", "c"])
      func foo(_ x: String) {}4️⃣
      """,
      uri: uri
    )

    let filename = uri.fileURL?.lastPathComponent ?? ""
    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "foo(_:)/\(filename):\(positions["1️⃣"].line + 1):\(positions["1️⃣"].utf16index + 2)",
          label: "foo(_:)",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"])
        ),
        TestItem(
          id: "foo(_:)/\(filename):\(positions["3️⃣"].line + 1):\(positions["3️⃣"].utf16index + 2)",
          label: "foo(_:)",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"])
        ),
      ]
    )
  }

  func testSwiftTestingTestsWithDuplicateFunctionIdentifiersInSuite() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MySuite {
        3️⃣@Test(arguments: [1, 2, 3])
        func foo(_ x: Int) {}4️⃣
        5️⃣@Test(arguments: ["a", "b", "c"])
        func foo(_ x: String) {}6️⃣
      }2️⃣
      """,
      uri: uri
    )

    let filename = uri.fileURL?.lastPathComponent ?? ""
    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MySuite",
          label: "MySuite",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [
            TestItem(
              id: "MySuite/foo(_:)/\(filename):\(positions["3️⃣"].line + 1):\(positions["3️⃣"].utf16index + 2)",
              label: "foo(_:)",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"])
            ),
            TestItem(
              id: "MySuite/foo(_:)/\(filename):\(positions["5️⃣"].line + 1):\(positions["5️⃣"].utf16index + 2)",
              label: "foo(_:)",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["5️⃣"]..<positions["6️⃣"])
            ),
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestsWithDuplicateFunctionIdentifiersInExtension() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing
      1️⃣struct MySuite {
        3️⃣@Test(arguments: [1, 2, 3])
        func foo(_ x: Int) {}4️⃣
      }2️⃣

      extension MySuite {
        5️⃣@Test(arguments: ["a", "b", "c"])
        func foo(_ x: String) {}6️⃣
      }
      """,
      uri: uri
    )

    let filename = uri.fileURL?.lastPathComponent ?? ""
    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MySuite",
          label: "MySuite",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [
            TestItem(
              id: "MySuite/foo(_:)/\(filename):\(positions["3️⃣"].line + 1):\(positions["3️⃣"].utf16index + 2)",
              label: "foo(_:)",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"])
            ),
            TestItem(
              id: "MySuite/foo(_:)/\(filename):\(positions["5️⃣"].line + 1):\(positions["5️⃣"].utf16index + 2)",
              label: "foo(_:)",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["5️⃣"]..<positions["6️⃣"])
            ),
          ]
        )
      ]
    )
  }

  func testSwiftTestingSuiteWithNoTests() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Suite
      struct MyTests {
      }2️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"])
        )
      ]
    )
  }

  func testSwiftTestingSuiteWithCustomName() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Suite("My tests")
      struct MyTests {
      }2️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "My tests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"])
        )
      ]
    )
  }

  func testSwiftTestingTestWithCustomName() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Test("One is two")
      func oneIsTwo() {
        #expect(1 == 2)
      }2️⃣

      3️⃣@Test("One is two")
      func `one is two`() {
        #expect(1 == 2)
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "oneIsTwo()",
          label: "One is two",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"])
        ),
        TestItem(
          id: "`one is two`()",
          label: "One is two",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"])
        ),
      ]
    )
  }

  func testSwiftTestingTestWithBackticksInName() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct `MyTests` {
        2️⃣@Test
        func `oneIsTwo`(`foo`: Int) {
          #expect(1 == 2)
        }3️⃣
      }4️⃣

      5️⃣extension `MyTests` {
        6️⃣@Test
        func `twoIsThree`() {
          #expect(2 == 3)
        }7️⃣
      }8️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo(foo:)",
              label: "oneIsTwo(foo:)",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            ),
            TestItem(
              id: "MyTests/twoIsThree()",
              label: "twoIsThree()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["6️⃣"]..<positions["7️⃣"])
            ),
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestWithRawIdentifiers() async throws {
    try await SkipUnless.haveRawIdentifiers()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test
        func `one two`(`a b`: Int, c: Int, `3`: Int, `$`: Int, `+1`: Int) {
          #expect(1 == 2)
        }3️⃣
      }4️⃣

      extension MyTests {
        5️⃣@Test
        func `3four`() {
          #expect(2 == 3)
        }6️⃣
        // Don't include operators
        @Test
        func +() {
          #expect(2 == 3)
        }
        // This is invalid, but we'll pick it up as identifier.
        7️⃣@Test
        func `+`() {
          #expect(2 == 3)
        }8️⃣
        // Also invalid.
        9️⃣@Test
        func ``() {
          #expect(2 == 3)
        }🔟
      }
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/`one two`(`a b`:c:`3`:`$`:`+1`:)",
              label: "one two",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            ),
            TestItem(
              id: "MyTests/`3four`()",
              label: "3four",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["5️⃣"]..<positions["6️⃣"])
            ),
            TestItem(
              id: "MyTests/`+`()",
              label: "+",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["7️⃣"]..<positions["8️⃣"])
            ),
            TestItem(
              id: "MyTests/``()",
              label: "``",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["9️⃣"]..<positions["🔟"])
            ),
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestWithNestedRawIdentifiers() async throws {
    try await SkipUnless.haveRawIdentifiers()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct `A B` {
        2️⃣struct `C` {
          3️⃣struct `D.E` {
            4️⃣@Test
            func `foo bar`() {
              #expect(1 == 2)
            }5️⃣
          }6️⃣
        }7️⃣
      }8️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "`A B`",
          label: "A B",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["8️⃣"]),
          children: [
            TestItem(
              id: "`A B`/C",
              label: "C",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["7️⃣"]),
              children: [
                TestItem(
                  id: "`A B`/C/`D.E`",
                  label: "D.E",
                  style: TestStyle.swiftTesting,
                  location: Location(uri: uri, range: positions["3️⃣"]..<positions["6️⃣"]),
                  children: [
                    TestItem(
                      id: "`A B`/C/`D.E`/`foo bar`()",
                      label: "foo bar",
                      style: TestStyle.swiftTesting,
                      location: Location(uri: uri, range: positions["4️⃣"]..<positions["5️⃣"])
                    )
                  ]
                )
              ]
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestWithNestedRawIdentifiersExtension() async throws {
    try await SkipUnless.haveRawIdentifiers()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      struct `A.B` {
        struct `C` {
          struct `D E` {}
        }
      }
      1️⃣extension `A.B`.`C`.`D E` {
        2️⃣@Test
        func `foo bar`() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      5️⃣extension `A.B` {
        6️⃣@Test
        func `bar baz`() {
          #expect(1 == 2)
        }7️⃣
      }8️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "`A.B`/C/`D E`",
          label: "D E",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "`A.B`/C/`D E`/`foo bar`()",
              label: "foo bar",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        ),
        TestItem(
          id: "`A.B`",
          label: "A.B",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["5️⃣"]..<positions["8️⃣"]),
          children: [
            TestItem(
              id: "`A.B`/`bar baz`()",
              label: "bar baz",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["6️⃣"]..<positions["7️⃣"])
            )
          ]
        ),
      ]
    )
  }

  func testSwiftTestingTestWithSlashRawIdentifiers() async throws {
    try await SkipUnless.haveRawIdentifiers()

    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test
        func `x/y`() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/`x/y`()",
              label: "x/y",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestDisabledTest() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Test("One is two", .disabled())
      func oneIsTwo() {
        #expect(1 == 2)
      }2️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "oneIsTwo()",
          label: "One is two",
          disabled: true,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"])
        )
      ]
    )
  }

  func testSwiftTestingTestInDisabledSuite() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Suite(.disabled())
      struct MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: true,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: true,
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingHiddenTest() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    testClient.openDocument(
      """
      import Testing

      @Test("One is two", .hidden)
      func oneIsTwo() {
        #expect(1 == 2)
      }
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      []
    )
  }

  func testSwiftTestingTestWithTags() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Suite(.tags(.green))
      struct MyTests {
        2️⃣@Test(.tags(.red, .blue))
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              tags: [TestTag(id: "red"), TestTag(id: "blue")]
            )
          ],
          tags: [TestTag(id: "green")]
        )
      ]
    )
  }

  func testSwiftTestingTestWithCustomTags() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      extension Tag {
        @Tag static var suite: Self
        @Tag static var foo: Self
        @Tag static var bar: Self
        @Tag static var baz: Self

        struct Nested {
          @Tag static var foo: Tag
        }
      }

      1️⃣@Suite(.tags(.suite))
      struct MyTests {
        2️⃣@Test(.tags(.foo, Nested.foo, Testing.Tag.bar, Tag.baz))
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              tags: [
                TestTag(id: "foo"),
                TestTag(id: "Nested.foo"),
                TestTag(id: "bar"),
                TestTag(id: "baz"),
              ]
            )
          ],
          tags: [TestTag(id: "suite")]
        )
      ]
    )
  }

  func testSwiftTestingTestsWithExtension() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣struct MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣

      5️⃣extension MyTests {
        6️⃣@Test
        func twoIsThree() {
          #expect(2 == 3)
        }7️⃣
      }8️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            ),
            TestItem(
              id: "MyTests/twoIsThree()",
              label: "twoIsThree()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["6️⃣"]..<positions["7️⃣"])
            ),
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestSuitesWithExtension() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import XCTest

      1️⃣@Suite struct MyTests {
        2️⃣@Test func oneIsTwo() {}3️⃣
      }4️⃣

      extension MyTests {
        5️⃣@Test func twoIsThree() {}6️⃣
      }
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            ),
            TestItem(
              id: "MyTests/twoIsThree()",
              label: "twoIsThree()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["5️⃣"]..<positions["6️⃣"])
            ),
          ]
        )
      ]
    )
  }

  func testSwiftTestingNestedTestSuiteWithExtension() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Suite struct Outer {
        3️⃣@Suite struct Inner {
          5️⃣@Test func oneIsTwo {}6️⃣
        }4️⃣
      }2️⃣

      extension Outer.Inner {
        7️⃣@Test func twoIsThree() {}8️⃣
      }
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "Outer",
          label: "Outer",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [
            TestItem(
              id: "Outer/Inner",
              label: "Inner",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"]),
              children: [
                TestItem(
                  id: "Outer/Inner/oneIsTwo()",
                  label: "oneIsTwo()",
                  style: TestStyle.swiftTesting,
                  location: Location(uri: uri, range: positions["5️⃣"]..<positions["6️⃣"])
                ),
                TestItem(
                  id: "Outer/Inner/twoIsThree()",
                  label: "twoIsThree()",
                  style: TestStyle.swiftTesting,
                  location: Location(uri: uri, range: positions["7️⃣"]..<positions["8️⃣"])
                ),
              ]
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingExtensionOfTypeInAnotherFile() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣extension MyTests {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingExtensionOfNestedType() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      struct MyTests {
        struct Inner {}
      }

      1️⃣extension MyTests.Inner {
        2️⃣@Test
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests/Inner",
          label: "Inner",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/Inner/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingTwoExtensionsNoDeclaration() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣extension MyTests {
        3️⃣@Test func oneIsTwo() {}4️⃣
      }2️⃣

      extension MyTests {
        5️⃣@Test func twoIsThree() {}6️⃣
      }
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"]),
              children: [],
              tags: []
            ),
            TestItem(
              id: "MyTests/twoIsThree()",
              label: "twoIsThree()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["5️⃣"]..<positions["6️⃣"])
            ),
          ]
        )
      ]
    )
  }

  func testSwiftTestingEnumSuite() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣enum MyTests {
        2️⃣@Test
        static func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingActorSuite() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣actor MyTests {
        2️⃣@Test
        static func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingFullyQualifyTestAttribute() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import Testing

      1️⃣@Testing.Suite("My Tests")
      struct MyTests {
        2️⃣@Testing.Test("one is two")
        func oneIsTwo() {
          #expect(1 == 2)
        }3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "My Tests",
          style: TestStyle.swiftTesting,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "one is two",
              style: TestStyle.swiftTesting,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testXCTestTestsWithExtension() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import XCTest

      1️⃣final class MyTests: XCTestCase {}2️⃣

      extension MyTests {
        3️⃣func testOneIsTwo() {}4️⃣
      }
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testOneIsTwo()",
              label: "testOneIsTwo()",
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testXCTestIndexedTestsWithExtension() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      import XCTest

      1️⃣final class MyTests: XCTestCase {}2️⃣

      extension MyTests {
        3️⃣func testOneIsTwo() {}4️⃣
      }
      """,
      allowBuildFailure: true
    )

    let tests = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(project.fileURI))
    )
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          location: Location(uri: project.fileURI, range: project.positions["1️⃣"]..<project.positions["2️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testOneIsTwo()",
              label: "testOneIsTwo()",
              location: Location(uri: project.fileURI, range: project.positions["3️⃣"]..<project.positions["4️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testXCTestIndexedTestsWithExtensionInSeparateFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class MyTests: XCTestCase {
        }
        """,
        "Tests/MyLibraryTests/MoreTests.swift": """
        import XCTest

        1️⃣extension MyTests {
          3️⃣func testMe() {}4️⃣
        }2️⃣
        """,
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("MoreTests.swift")

    let tests = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri))
    )
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testMe()",
              label: "testMe()",
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["4️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testXCTestInvalidXCTestSuiteConstructions() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import XCTest

      // This comment contains the string XCTestCase
      final class NSObjectInheritance: NSObject {}
      final class BaseClass {}
      final class MyEmptyTests: BaseClass {}
      1️⃣final class MyTests: XCTestCase {
        static func testStaticFuncIsNotATest() {}
      }2️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))

    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["2️⃣"]),
          children: []
        )
      ]
    )
  }

  func testAddNewMethodToNotQuiteTestCase() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      import XCTest

      class NotQuiteTest: SomeClass {
        func testMyLibrary() {}
      2️⃣
      }
      """,
      allowBuildFailure: true
    )

    let testsBeforeEdit = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(project.fileURI))
    )
    XCTAssertEqual(testsBeforeEdit, [])
    project.testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(project.fileURI, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: Range(project.positions["2️⃣"]), text: "func testSomethingElse() {}")
        ]
      )
    )
    let testsAfterEdit = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(project.fileURI))
    )
    XCTAssertEqual(testsAfterEdit, [])
  }

  func testAddNewClassToNotQuiteTestCase() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      import XCTest

      class NotQuiteTest: SomeClass {
        func testMyLibrary() {}
      }
      2️⃣
      """,
      allowBuildFailure: true
    )

    let testsBeforeEdit = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(project.fileURI))
    )
    XCTAssertEqual(testsBeforeEdit, [])
    project.testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(project.fileURI, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(
            range: Range(project.positions["2️⃣"]),
            text: """
              class OtherNotQuiteTest: SomeClass {
                func testSomethingElse() {}
              }
              """
          )
        ]
      )
    )
    let testsAfterEdit = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(project.fileURI))
    )
    // We know from the semantic index that NotQuiteTest does not inherit from XCTestCase, so we should not include it.
    // We don't have any semantic knowledge about `OtherNotQuiteTest`, so we are conservative and should include it.
    XCTAssertFalse(testsAfterEdit.contains { $0.label == "NotQuiteTest" })
    XCTAssertTrue(testsAfterEdit.contains { $0.label == "OtherNotQuiteTest" })
  }

  func testObjectiveCTestFromSemanticIndex() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/Test.m": """
        #import <XCTest/XCTest.h>

        @interface MyTests : XCTestCase
        @end

        1️⃣@implementation MyTests
        2️⃣- (void)testSomething {
        }3️⃣
        @4️⃣end
        """
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("Test.m")

    let tests = try await project.testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))

    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testSomething",
              label: "testSomething",
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testObjectiveCTestsAfterInMemoryEdit() async throws {
    try SkipUnless.platformIsDarwin("Non-Darwin platforms don't support Objective-C")
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/Test.m": """
        #import <XCTest/XCTest.h>

        @interface MyTests : XCTestCase
        @end

        1️⃣@implementation MyTests
        2️⃣- (void)testSomething {}3️⃣
        0️⃣
        @4️⃣end
        """
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("Test.m")

    project.testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(
            range: Range(positions["0️⃣"]),
            text: """
              - (void)testSomethingElse {}
              """
          )
        ]
      )
    )

    let tests = try await project.testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    // Since we don't have syntactic test discovery for clang-languages, we don't discover `testSomethingElse` as a
    // test method until we perform a build
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testSomething",
              label: "testSomething",
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestsAreNotReportedInNonTestTargets() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "FileA.swift": """
          @Suite struct MyTests {
          @Test func inStruct() {}
        }
        """
      ]
    )

    let (uri, _) = try project.openDocument("FileA.swift")

    let tests = try await project.testClient.send(DocumentTestsRequest(textDocument: TextDocumentIdentifier(uri)))
    XCTAssertEqual(tests, [])
  }

  func testXCTestsInInactiveIfRegionsAreDiscovered() async throws {
    // XCTest declarations inside inactive `#if` branches are not indexed by the semantic index because
    // the compiler never sees them. Verify that they are still surfaced via syntactic scanning of the
    // inactive region after the semantic index is available.
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      import XCTest

      // Active test class – found by the semantic index.
      1️⃣class ActiveTests: XCTestCase {
        2️⃣func testActiveMethod() {}3️⃣
      }4️⃣

      // Inactive region – the compiler never compiles this, so the semantic index
      // won't have an entry for it.  We expect syntactic scanning to pick it up.
      #if false
      5️⃣class InactiveTests: XCTestCase {
        6️⃣func testInactiveMethod() {}7️⃣
      }8️⃣
      #endif
      """,
      allowBuildFailure: true
    )

    let tests = try await project.testClient.send(
      DocumentTestsRequest(textDocument: TextDocumentIdentifier(project.fileURI))
    )

    // Both the active-region class (from the index) and the inactive-region class
    // (found syntactically) should be present.
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "ActiveTests",
          label: "ActiveTests",
          location: Location(
            uri: project.fileURI,
            range: project.positions["1️⃣"]..<project.positions["4️⃣"]
          ),
          children: [
            TestItem(
              id: "ActiveTests/testActiveMethod()",
              label: "testActiveMethod()",
              location: Location(
                uri: project.fileURI,
                range: project.positions["2️⃣"]..<project.positions["3️⃣"]
              )
            )
          ]
        ),
        TestItem(
          id: "InactiveTests",
          label: "InactiveTests",
          location: Location(
            uri: project.fileURI,
            range: project.positions["5️⃣"]..<project.positions["8️⃣"]
          ),
          children: [
            TestItem(
              id: "InactiveTests/testInactiveMethod()",
              label: "testInactiveMethod()",
              location: Location(
                uri: project.fileURI,
                range: project.positions["6️⃣"]..<project.positions["7️⃣"]
              )
            )
          ]
        ),
      ]
    )
  }
}
