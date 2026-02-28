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

@_spi(Testing) import BuildServerIntegration
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKLogging
import SKTestSupport
import SemanticIndex
@_spi(Testing) import SourceKitLSP
import SwiftExtensions
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

import struct TSCBasic.AbsolutePath

private let packageManifestWithTestTarget = """
  let package = Package(
    name: "MyLibrary",
    targets: [.testTarget(name: "MyLibraryTests")]
  )
  """

final class WorkspaceTestDiscoveryTests: SourceKitLSPTestCase {
  func testIndexBasedWorkspaceXCTests() async throws {
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
        """
      ],
      manifest: packageManifestWithTestTarget,
      enableBackgroundIndexing: true
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
            )
          ]
        )
      ]
    )
  }

  func testSyntacticWorkspaceXCTests() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        1️⃣class MyTests: XCTestCase {
          2️⃣func testMyLibrary() {}3️⃣
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }4️⃣
        """
      ],
      manifest: packageManifestWithTestTarget
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
            )
          ]
        )
      ]
    )
  }

  func testSyntacticOrIndexBasedXCTestsBasedOnWhetherFileIsIndexed() async throws {
    try SkipUnless.longTestsEnabled()

    let initialIndexingFinished = AtomicBool(initialValue: false)
    let syntacticWorkspaceRequestSent = WrappedSemaphore(name: "Syntactic workspace request sent")

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        1️⃣class MyTests: XCTestCase {
          2️⃣func testMyLibrary() {}3️⃣
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }4️⃣
        """
      ],
      manifest: packageManifestWithTestTarget,
      hooks: Hooks(
        indexHooks: IndexHooks(updateIndexStoreTaskDidStart: { _ in
          if initialIndexingFinished.value {
            syntacticWorkspaceRequestSent.waitOrXCTFail()
          }
        })
      ),
      enableBackgroundIndexing: true
    )

    initialIndexingFinished.value = true

    let myTestsUri = try project.uri(for: "MyTests.swift")

    // First get the tests from the original file contents, which are computed by the semantic index.

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
            )
          ]
        )
      ]
    )

    // Now update the file on disk and recompute tests. This should give use tests using the syntactic index, which will
    // include the tests in here even though `NotQuiteTests` doesn't inherit from XCTest

    let (_, newFilePositions) = try await project.changeFileOnDisk(
      "MyTests.swift",
      newMarkedContents: """
        import XCTest

        class ClassThatMayInheritFromXCTest {}

        5️⃣class NotQuiteTests: ClassThatMayInheritFromXCTest {
          6️⃣func testSomething() {}7️⃣
        }8️⃣
        """
    )

    let testsAfterDocumentChanged = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      testsAfterDocumentChanged,
      [
        TestItem(
          id: "MyLibraryTests.NotQuiteTests",
          label: "NotQuiteTests",
          location: Location(
            uri: myTestsUri,
            range: newFilePositions["5️⃣"]..<newFilePositions["8️⃣"]
          ),
          children: [
            TestItem(
              id: "MyLibraryTests.NotQuiteTests/testSomething()",
              label: "testSomething()",
              location: Location(
                uri: myTestsUri,
                range: newFilePositions["6️⃣"]..<newFilePositions["7️⃣"]
              )
            )
          ]
        )
      ]
    )

    syntacticWorkspaceRequestSent.signal()

    // After building again, we should have updated the updated the semantic index and realize that `NotQuiteTests` does
    // not inherit from XCTest and thus doesn't have any test methods.

    try await SwiftPMTestProject.build(at: project.scratchDirectory)

    let testsAfterRebuild = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(testsAfterRebuild, [])
  }

  func testWorkspaceSwiftTestingTests() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import Testing

        1️⃣struct MyTests {
          2️⃣@Test
          func oneIsTwo() {
            #expect(1 == 2)
          }3️⃣
        }4️⃣
        """
      ],
      manifest: packageManifestWithTestTarget
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
            )
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestsWithDuplicateFunctionIdentifiersAcrossDocuments() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests1.swift": """
        import Testing

        1️⃣@Test(arguments: [1, 2, 3])
        private func foo(_ x: Int) {}2️⃣
        """,
        "Tests/MyLibraryTests/MyTests2.swift": """
        import Testing

        3️⃣@Test(arguments: [1, 2, 3])
        private func foo(_ x: Int) {}4️⃣
        """,
      ],
      manifest: packageManifestWithTestTarget
    )

    let test1Position = try project.position(of: "1️⃣", in: "MyTests1.swift")
    let test2Position = try project.position(of: "3️⃣", in: "MyTests2.swift")

    let tests = try await project.testClient.send(WorkspaceTestsRequest())

    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.foo(_:)/MyTests1.swift:\(test1Position.line + 1):\(test1Position.utf16index + 2)",
          label: "foo(_:)",
          style: TestStyle.swiftTesting,
          location: try project.location(from: "1️⃣", to: "2️⃣", in: "MyTests1.swift")
        ),
        TestItem(
          id: "MyLibraryTests.foo(_:)/MyTests2.swift:\(test2Position.line + 1):\(test2Position.utf16index + 2)",
          label: "foo(_:)",
          style: TestStyle.swiftTesting,
          location: try project.location(from: "3️⃣", to: "4️⃣", in: "MyTests2.swift")
        ),
      ]
    )
  }

  func testSwiftTestingAndXCTestInTheSameFile() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import Testing
        import XCTest

        1️⃣struct MyTests {
          2️⃣@Test
          func oneIsTwo() {
            #expect(1 == 2)
          }3️⃣
        }4️⃣

        5️⃣class MyOldTests: XCTestCase {
          6️⃣func testOld() {}7️⃣
        }8️⃣
        """
      ],
      manifest: packageManifestWithTestTarget,
      enableBackgroundIndexing: true
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              style: TestStyle.swiftTesting,
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
            )
          ],
          tags: []
        ),
        TestItem(
          id: "MyLibraryTests.MyOldTests",
          label: "MyOldTests",
          location: try project.location(from: "5️⃣", to: "8️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests.MyOldTests/testOld()",
              label: "testOld()",
              location: try project.location(from: "6️⃣", to: "7️⃣", in: "MyTests.swift")
            )
          ]
        ),
      ]
    )
  }

  func testTargetWithCustomModuleName() async throws {
    let packageManifestWithCustomModuleName = """
      let package = Package(
        name: "MyLibrary",
        targets: [
          .testTarget(
            name: "MyLibraryTests",
            swiftSettings: [
              .unsafeFlags(["-module-name", "Foo", "-module-name", "Bar"])
            ]
          )
        ]
      )
      """

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        1️⃣class MyTests: XCTestCase {
          2️⃣func testMyLibrary() {}3️⃣
        }4️⃣
        """
      ],
      manifest: packageManifestWithCustomModuleName
    )

    // Last argument takes precedence, so expect Bar as the module name.

    let tests = try await project.testClient.send(WorkspaceTestsRequest())

    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "Bar.MyTests",
          label: "MyTests",
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "Bar.MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
            )
          ]
        )
      ]
    )
  }

  func testMultipleTargetsWithSameXCTestClassName() async throws {
    let packageManifestWithTwoTestTargets = """
      let package = Package(
        name: "MyLibrary",
        targets: [.testTarget(name: "MyLibraryTests"), .testTarget(name: "MyLibraryTests2")]
      )
      """

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        1️⃣class MyTests: XCTestCase {
          2️⃣func testMyLibrary() {}3️⃣
        }4️⃣
        """,
        "Tests/MyLibraryTests2/MyTests2.swift": """
        import XCTest

        5️⃣class MyTests: XCTestCase {
          6️⃣func testMyLibrary() {}7️⃣
        }8️⃣
        """,
      ],
      manifest: packageManifestWithTwoTestTargets
    )
    let tests = try await project.testClient.send(WorkspaceTestsRequest())

    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
            )
          ]
        ),
        TestItem(
          id: "MyLibraryTests2.MyTests",
          label: "MyTests",
          location: try project.location(from: "5️⃣", to: "8️⃣", in: "MyTests2.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests2.MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: try project.location(from: "6️⃣", to: "7️⃣", in: "MyTests2.swift")
            )
          ]
        ),
      ]
    )
  }

  func testWorkspaceTestsForInMemoryEditedFile() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        1️⃣class MyTests: XCTestCase {
          2️⃣func testMyLibrary0️⃣() {
          }3️⃣
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }4️⃣
        """
      ],
      manifest: packageManifestWithTestTarget,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("MyTests.swift")

    // If the document has been opened but not modified in-memory, we can still use the semantic index and detect that
    // `MyTests` does not inherit from `XCTestCase`.
    let testsAfterDocumentOpen = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      testsAfterDocumentOpen,
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

    project.testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [
          TextDocumentContentChangeEvent(range: Range(positions["0️⃣"]), text: "Updated")
        ]
      )
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testMyLibraryUpdated()",
              label: "testMyLibraryUpdated()",
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testWorkspaceTestsAfterOneFileHasBeenEdited() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyFirstTests.swift": """
        import XCTest

        1️⃣class MyFirstTests: XCTestCase {
          2️⃣func testOne0️⃣() {
          }3️⃣
        }4️⃣
        """,
        "Tests/MyLibraryTests/MySecondTests.swift": """
        import XCTest

        5️⃣class MySecondTests: XCTestCase {
          6️⃣func testTwo() {}7️⃣
        }8️⃣
        """,
      ],
      manifest: packageManifestWithTestTarget,
      enableBackgroundIndexing: true
    )

    let (uri, positions) = try project.openDocument("MyFirstTests.swift")
    project.testClient.send(
      DidChangeTextDocumentNotification(
        textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
        contentChanges: [TextDocumentContentChangeEvent(range: Range(positions["0️⃣"]), text: "Updated")]
      )
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyFirstTests",
          label: "MyFirstTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyFirstTests/testOneUpdated()",
              label: "testOneUpdated()",
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        ),
        TestItem(
          id: "MyLibraryTests.MySecondTests",
          label: "MySecondTests",
          location: try project.location(from: "5️⃣", to: "8️⃣", in: "MySecondTests.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests.MySecondTests/testTwo()",
              label: "testTwo()",
              location: try project.location(from: "6️⃣", to: "7️⃣", in: "MySecondTests.swift")
            )
          ]
        ),
      ]
    )
  }

  func testRemoveFileWithSemanticIndex() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class 1️⃣MyTests: XCTestCase {
          func 2️⃣testSomething() {
          }
        }
        """
      ],
      manifest: packageManifestWithTestTarget,
      enableBackgroundIndexing: true
    )

    try await project.changeFileOnDisk("MyTests.swift", newMarkedContents: nil)

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(tests, [])
  }

  func testRemoveFileWithSyntacticIndex() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class 1️⃣MyTests: XCTestCase {
          func 2️⃣testSomething() {
          }
        }
        """
      ],
      manifest: packageManifestWithTestTarget
    )

    try await project.changeFileOnDisk("MyTests.swift", newMarkedContents: nil)

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(tests, [])
  }

  func testAddFileToSyntacticIndex() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": ""
      ],
      manifest: packageManifestWithTestTarget
    )

    let (uri, positions) = try await project.changeFileOnDisk(
      "MyTests.swift",
      newMarkedContents: """
        import XCTest

        1️⃣class 2️⃣MyTests: XCTestCase {
          3️⃣func 4️⃣testSomething() {}5️⃣
        }6️⃣
        """
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["6️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testSomething()",
              label: "testSomething()",
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["5️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testInMemoryFileWithFallbackBuildServer() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)

    let positions = testClient.openDocument(
      """
      import XCTest

      1️⃣class MyTests: XCTestCase {
        2️⃣func testSomething() {}3️⃣
      }4️⃣
      """,
      uri: uri
    )

    let tests = try await testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testSomething()",
              label: "testSomething()",
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testIndexedFileWithCompilationDbBuildServer() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await IndexedSingleSwiftFileTestProject(
      """
      import XCTest

      1️⃣class MyTests: XCTestCase {
        2️⃣func testSomething() {}3️⃣
      }4️⃣
      """
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          location: Location(uri: project.fileURI, range: project.positions["1️⃣"]..<project.positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testSomething()",
              label: "testSomething()",
              location: Location(uri: project.fileURI, range: project.positions["2️⃣"]..<project.positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testOnDiskFileWithCompilationDbBuildServer() async throws {
    let project = try await MultiFileTestProject(files: [
      "MyTests.swift": """
      import XCTest

      1️⃣class MyTests: XCTestCase {
        2️⃣func testSomething() {}3️⃣
      }4️⃣
      """,
      "compile_commands.json": "[]",
    ])

    // When MyTests.swift is not part of the compilation database, the build server doesn't know about the file and thus
    // doesn't return any tests for it.
    let testsWithEmptyCompilationDatabase = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(testsWithEmptyCompilationDatabase, [])

    let swiftc = try await unwrap(ToolchainRegistry.forTesting.default?.swiftc)
    let uri = try project.uri(for: "MyTests.swift")

    let compilationDatabase = JSONCompilationDatabase(
      [
        CompilationDatabaseCompileCommand(
          directory: try project.scratchDirectory.filePath,
          filename: uri.pseudoPath,
          commandLine: [try swiftc.filePath, uri.pseudoPath]
        )
      ],
      compileCommandsDirectory: project.scratchDirectory
    )

    try await project.changeFileOnDisk(
      JSONCompilationDatabaseBuildServer.dbName,
      newMarkedContents: XCTUnwrap(String(data: JSONEncoder().encode(compilationDatabase), encoding: .utf8))
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyTests/testSomething()",
              label: "testSomething()",
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
            )
          ]
        )
      ]
    )
  }

  func testDeleteFileAndAddItAgain() async throws {
    let markedFileContents = """
      import XCTest

      1️⃣class MyTests: XCTestCase {
        2️⃣func testMyLibrary() {}3️⃣
        func unrelatedFunc() {}
        var testVariable: Int = 0
      }4️⃣
      """

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": markedFileContents
      ],
      manifest: packageManifestWithTestTarget
    )

    let expectedTests = [
      TestItem(
        id: "MyLibraryTests.MyTests",
        label: "MyTests",
        location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
        children: [
          TestItem(
            id: "MyLibraryTests.MyTests/testMyLibrary()",
            label: "testMyLibrary()",
            location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
          )
        ]
      )
    ]

    let testsBeforeFileRemove = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(testsBeforeFileRemove, expectedTests)

    try await project.changeFileOnDisk("MyTests.swift", newMarkedContents: nil)

    let testsAfterFileRemove = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(testsAfterFileRemove, [])

    try await project.changeFileOnDisk("MyTests.swift", newMarkedContents: markedFileContents)

    let testsAfterFileReAdded = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(testsAfterFileReAdded, expectedTests)
  }

  func testDontIncludeTestsFromDependentPackageInSyntacticIndex() async throws {
    let dependencyProject = try await SwiftPMDependencyProject(files: [
      "Sources/MyDependency/MyDependency.swift": """
      class MySuperclass {}
      class LooksALittleLikeTests: MySuperclass {
        func testSomething() {}
      }
      """
    ])
    defer { dependencyProject.keepAlive() }

    let project = try await SwiftPMTestProject(
      files: [
        "Test.swift": ""
      ],
      manifest: """
        let package = Package(
          name: "MyLibrary",
          dependencies: [.package(url: "\(dependencyProject.packageDirectory)", from: "1.0.0")],
          targets: [
            .target(
              name: "MyLibrary",
              dependencies: [.product(name: "MyDependency", package: "MyDependency")]
            )
          ]
        )
        """,
      workspaces: { scratchDirectory in
        try await SwiftPMTestProject.resolvePackageDependencies(at: scratchDirectory)
        return [WorkspaceFolder(uri: DocumentURI(scratchDirectory))]
      }
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(tests, [])
  }

  func testAddNewClassToNotQuiteTestCase() async throws {
    let originalContents = """
      import XCTest

      class NotQuiteTest: SomeClass {
        func testMyLibrary() {}
      }

      """

    let project = try await IndexedSingleSwiftFileTestProject(originalContents, allowBuildFailure: true)
    // Close the file so we don't have an in-memory version of it.
    project.testClient.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(project.fileURI)))

    let testsBeforeEdit = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(testsBeforeEdit, [])

    let addedTest = """
      class OtherNotQuiteTest: SomeClass {
        func testSomethingElse() {}
      }
      """

    let uri = try XCTUnwrap(project.fileURI.fileURL)

    try await (originalContents + addedTest).writeWithRetry(to: uri)

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: project.fileURI, type: .changed)])
    )
    // Ensure that we handle the `DidChangeWatchedFilesNotification`.
    try await project.testClient.send(SynchronizeRequest())

    let testsAfterEdit = try await project.testClient.send(WorkspaceTestsRequest())
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

        @implementation 1️⃣MyTests
        - (void)2️⃣testSomething {
        }
        @end
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

    let tests = try await project.testClient.send(WorkspaceTestsRequest())

    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: try project.location(from: "1️⃣", to: "1️⃣", in: "Test.m"),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testSomething",
              label: "testSomething",
              location: try project.location(from: "2️⃣", to: "2️⃣", in: "Test.m")
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

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
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

  func testSwiftTestingExtensionAcrossMultipleFiles() async throws {
    let fileAContents = """
      extension MyTests {
        5️⃣@Test func inExtension() {}6️⃣
      }
      """

    let fileBContents = """
      1️⃣@Suite struct MyTests {
        3️⃣@Test func inStruct() {}4️⃣
      }2️⃣
      """

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/FileA.swift": fileAContents,
        "Tests/MyLibraryTests/FileB.swift": fileBContents,
      ],
      manifest: packageManifestWithTestTarget
    )

    let (fileAURI, fileAPositions) = try project.openDocument("FileA.swift")
    let (fileBURI, fileBPositions) = try project.openDocument("FileB.swift")

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          style: TestStyle.swiftTesting,
          location: Location(uri: fileBURI, range: fileBPositions["1️⃣"]..<fileBPositions["2️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/inStruct()",
              label: "inStruct()",
              style: TestStyle.swiftTesting,
              location: Location(uri: fileBURI, range: fileBPositions["3️⃣"]..<fileBPositions["4️⃣"])
            ),
            TestItem(
              id: "MyLibraryTests.MyTests/inExtension()",
              label: "inExtension()",
              style: TestStyle.swiftTesting,
              location: Location(uri: fileAURI, range: fileAPositions["5️⃣"]..<fileAPositions["6️⃣"])
            ),
          ]
        )
      ]
    )
  }

  func testSwiftTestingTestsAreNotDiscoveredInNonTestTargets() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "FileA.swift": """
          @Suite struct MyTests {
          @Test func inStruct() {}
        }
        """
      ]
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(tests, [])
  }

  // MARK: - workspace/tests/refresh opt-in tests

  func testInitialRefreshIsSentOnStartup() async throws {
    let refreshReceived = self.expectation(description: "Initial workspace/tests/refresh received")
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        1️⃣class MyTests: XCTestCase {
          2️⃣func testMyLibrary() {}3️⃣
        }4️⃣
        """
      ],
      manifest: packageManifestWithTestTarget,
      capabilities: ClientCapabilities(experimental: [
        WorkspaceTestsRefreshRequest.method: .bool(true)
      ]),
      preInitialization: { testClient in
        testClient.handleSingleRequest { (_: WorkspaceTestsRefreshRequest) in
          refreshReceived.fulfill()
          return VoidResponse()
        }
      }
    )
    try await fulfillmentOfOrThrow(refreshReceived)

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift")
            )
          ]
        )
      ]
    )
  }

  func testRefreshIsSentAfterFileChangedOnDisk() async throws {
    let initialRefresh = self.expectation(description: "Initial workspace/tests/refresh")
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        1️⃣class MyTests: XCTestCase {
          2️⃣func testMyLibrary() {}3️⃣
        }4️⃣
        """
      ],
      manifest: packageManifestWithTestTarget,
      capabilities: ClientCapabilities(experimental: [
        WorkspaceTestsRefreshRequest.method: .bool(true)
      ]),
      preInitialization: { testClient in
        testClient.handleSingleRequest { (_: WorkspaceTestsRefreshRequest) in
          initialRefresh.fulfill()
          return VoidResponse()
        }
      }
    )

    // Drain the initial refresh.
    try await fulfillmentOfOrThrow(initialRefresh)

    // Now change the file and wait for the follow-up refresh.
    let (uri, newPositions) = try await project.testClient.withWaitingFor(WorkspaceTestsRefreshRequest.self) {
      try await project.changeFileOnDisk(
        "MyTests.swift",
        newMarkedContents: """
          import XCTest

          5️⃣class MyTests: XCTestCase {
            6️⃣func testRenamedMethod() {}7️⃣
          }8️⃣
          """,
        synchronize: false
      )
    }

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyLibraryTests.MyTests",
          label: "MyTests",
          location: Location(uri: uri, range: newPositions["5️⃣"]..<newPositions["8️⃣"]),
          children: [
            TestItem(
              id: "MyLibraryTests.MyTests/testRenamedMethod()",
              label: "testRenamedMethod()",
              location: Location(uri: uri, range: newPositions["6️⃣"]..<newPositions["7️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testRefreshIsSentAfterFileDeleted() async throws {
    let initialRefresh = self.expectation(description: "Initial workspace/tests/refresh")
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class MyTests: XCTestCase {
          func testMyLibrary() {}
        }
        """
      ],
      manifest: packageManifestWithTestTarget,
      capabilities: ClientCapabilities(experimental: [
        WorkspaceTestsRefreshRequest.method: .bool(true)
      ]),
      preInitialization: { testClient in
        testClient.handleSingleRequest { (_: WorkspaceTestsRefreshRequest) in
          initialRefresh.fulfill()
          return VoidResponse()
        }
      }
    )

    // Drain the initial refresh.
    try await fulfillmentOfOrThrow(initialRefresh)

    // Delete the file and wait for the follow-up refresh.
    try await project.testClient.withWaitingFor(WorkspaceTestsRefreshRequest.self) {
      try await project.changeFileOnDisk("MyTests.swift", newMarkedContents: nil, synchronize: false)
    }

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(tests, [])
  }

  func testRefreshIsSentAfterFileAdded() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": ""
      ],
      manifest: packageManifestWithTestTarget,
      capabilities: ClientCapabilities(experimental: [
        WorkspaceTestsRefreshRequest.method: .bool(true)
      ])
    )

    // The initial file is empty so no tests are discovered and no initial refresh is sent.
    // Add test content to the file and wait for the refresh.
    let (uri, positions) = try await project.testClient.withWaitingFor(WorkspaceTestsRefreshRequest.self) {
      try await project.changeFileOnDisk(
        "MyTests.swift",
        newMarkedContents: """
          import XCTest

          1️⃣class MyTests: XCTestCase {
            2️⃣func testMyLibrary() {}3️⃣
          }4️⃣
          """,
        synchronize: false
      )
    }

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
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
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"])
            )
          ]
        )
      ]
    )
  }

  func testNoRefreshSentWhenTestsUnchanged() async throws {
    let initialRefresh = self.expectation(description: "Initial workspace/tests/refresh")
    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class MyTests: XCTestCase {
          func testMyLibrary() {}
        }
        """,
        "Tests/MyLibraryTests/Helper.swift": """
        func helperFunction() {}
        """,
      ],
      manifest: packageManifestWithTestTarget,
      capabilities: ClientCapabilities(experimental: [
        WorkspaceTestsRefreshRequest.method: .bool(true)
      ]),
      preInitialization: { testClient in
        testClient.handleSingleRequest { (_: WorkspaceTestsRefreshRequest) in
          initialRefresh.fulfill()
          return VoidResponse()
        }
      }
    )

    // Drain the initial refresh.
    try await fulfillmentOfOrThrow(initialRefresh)

    // Install a persistent handler that fails if any unexpected refresh arrives.
    project.testClient.handleMultipleRequests { (_: WorkspaceTestsRefreshRequest) in
      XCTFail("Unexpected workspace/tests/refresh after non-test file change")
      return VoidResponse()
    }

    // Modify the non-test helper file.
    try await project.changeFileOnDisk(
      "Helper.swift",
      newMarkedContents: """
        // A comment was added
        func helperFunction() {}
        """
    )

    // Flush all pending processing.
    try await project.testClient.send(SynchronizeRequest())
  }

}

extension TestItem {
  init(
    id: String,
    label: String,
    disabled: Bool = false,
    style: String = TestStyle.xcTest,
    location: Location,
    children: [TestItem] = [],
    tags: [TestTag] = []
  ) {
    self.init(
      id: id,
      label: label,
      description: nil,
      sortText: nil,
      disabled: disabled,
      style: style,
      location: location,
      children: children,
      tags: tags
    )
  }
}
