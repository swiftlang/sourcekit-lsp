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

import Foundation
import LSPTestSupport
import LanguageServerProtocol
@_spi(Testing) import SKCore
import SKTestSupport
@_spi(Testing) import SourceKitLSP
import XCTest

private let packageManifestWithTestTarget = """
  // swift-tools-version: 5.7

  import PackageDescription

  let package = Package(
    name: "MyLibrary",
    targets: [.testTarget(name: "MyLibraryTests")]
  )
  """

final class WorkspaceTestDiscoveryTests: XCTestCase {
  func testIndexBasedWorkspaceXCTests() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class 1️⃣MyTests: XCTestCase {
          func 2️⃣testMyLibrary() {}
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }
        """
      ],
      manifest: packageManifestWithTestTarget,
      build: true
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(
            uri: try project.uri(for: "MyTests.swift"),
            range: Range(try project.position(of: "1️⃣", in: "MyTests.swift"))
          ),
          children: [
            TestItem(
              id: "MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(
                uri: try project.uri(for: "MyTests.swift"),
                range: Range(try project.position(of: "2️⃣", in: "MyTests.swift"))
              ),
              children: [],
              tags: []
            )
          ],
          tags: []
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
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              disabled: false,
              style: TestStyle.xcTest,
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift"),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testSyntacticOrIndexBasedXCTestsBasedOnWhetherFileIsIndexed() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await SwiftPMTestProject(
      files: [
        "Tests/MyLibraryTests/MyTests.swift": """
        import XCTest

        class 1️⃣MyTests: XCTestCase {
          func 2️⃣testMyLibrary() {}
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }
        """
      ],
      manifest: packageManifestWithTestTarget,
      build: true
    )

    let myTestsUri = try project.uri(for: "MyTests.swift")

    // First get the tests from the original file contents, which are computed by the semantic index.

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(
            uri: myTestsUri,
            range: Range(try project.position(of: "1️⃣", in: "MyTests.swift"))
          ),
          children: [
            TestItem(
              id: "MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(
                uri: myTestsUri,
                range: Range(try project.position(of: "2️⃣", in: "MyTests.swift"))
              ),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )

    // Now update the file on disk and recompute tests. This should give use tests using the syntactic index, which will
    // include the tests in here even though `NotQuiteTests` doesn't inherit from XCTest

    let newMarkedFileContents = """
      import XCTest

      class ClassThatMayInheritFromXCTest {}

      3️⃣class NotQuiteTests: ClassThatMayInheritFromXCTest {
        4️⃣func testSomething() {}5️⃣
      }6️⃣
      """
    let newFileContents = extractMarkers(newMarkedFileContents).textWithoutMarkers
    let newFilePositions = DocumentPositions(markedText: newMarkedFileContents)
    try newFileContents.write(to: try XCTUnwrap(myTestsUri.fileURL), atomically: true, encoding: .utf8)
    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: myTestsUri, type: .changed)]))

    let testsAfterDocumentChanged = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      testsAfterDocumentChanged,
      [
        TestItem(
          id: "NotQuiteTests",
          label: "NotQuiteTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(
            uri: myTestsUri,
            range: newFilePositions["3️⃣"]..<newFilePositions["6️⃣"]
          ),
          children: [
            TestItem(
              id: "NotQuiteTests/testSomething()",
              label: "testSomething()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(
                uri: myTestsUri,
                range: newFilePositions["4️⃣"]..<newFilePositions["5️⃣"]
              ),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )

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
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift"),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
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

        class 5️⃣MyOldTests: XCTestCase {
          func 6️⃣testOld() {}
        }
        """
      ],
      manifest: packageManifestWithTestTarget,
      build: true,
      allowBuildFailure: true
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyTests/oneIsTwo()",
              label: "oneIsTwo()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift"),
              children: [],
              tags: []
            )
          ],
          tags: []
        ),
        TestItem(
          id: "MyOldTests",
          label: "MyOldTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: try project.location(from: "5️⃣", to: "5️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyOldTests/testOld()",
              label: "testOld()",
              disabled: false,
              style: TestStyle.xcTest,
              location: try project.location(from: "6️⃣", to: "6️⃣", in: "MyTests.swift"),
              children: [],
              tags: []
            )
          ],
          tags: []
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

        1️⃣class 2️⃣MyTests: XCTestCase {
          3️⃣func 4️⃣testMyLibrary0️⃣() {
          }5️⃣
          func unrelatedFunc() {}
          var testVariable: Int = 0
        }6️⃣
        """
      ],
      manifest: packageManifestWithTestTarget,
      build: true
    )

    let (uri, positions) = try project.openDocument("MyTests.swift")

    // If the document has been opened but not modified in-memory, we can still use the semantic index and detect that
    // `MyTests` does not inherit from `XCTestCase`.
    let testsAfterDocumentOpen = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      testsAfterDocumentOpen,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: uri, range: positions["2️⃣"]..<positions["2️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testMyLibrary()",
              label: "testMyLibrary()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(uri: uri, range: positions["4️⃣"]..<positions["4️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )

    // After we have an in-memory change to the file, we can't use the semantic index to discover the tests anymore.
    // Use the syntactic index instead.
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
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["6️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testMyLibraryUpdated()",
              label: "testMyLibraryUpdated()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["5️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
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

        class 5️⃣MySecondTests: XCTestCase {
          func 6️⃣testTwo() {}
        }
        """,
      ],
      manifest: packageManifestWithTestTarget,
      build: true
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
          id: "MyFirstTests",
          label: "MyFirstTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyFirstTests/testOneUpdated()",
              label: "testOneUpdated()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(uri: uri, range: positions["2️⃣"]..<positions["3️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        ),
        TestItem(
          id: "MySecondTests",
          label: "MySecondTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: try project.location(from: "5️⃣", to: "5️⃣", in: "MySecondTests.swift"),
          children: [
            TestItem(
              id: "MySecondTests/testTwo()",
              label: "testTwo()",
              disabled: false,
              style: TestStyle.xcTest,
              location: try project.location(from: "6️⃣", to: "6️⃣", in: "MySecondTests.swift"),
              children: [],
              tags: []
            )
          ],
          tags: []
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
      build: true
    )

    let uri = try project.uri(for: "MyTests.swift")
    try FileManager.default.removeItem(at: XCTUnwrap(uri.fileURL))
    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: uri, type: .deleted)]))

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

    let uri = try project.uri(for: "MyTests.swift")
    try FileManager.default.removeItem(at: XCTUnwrap(uri.fileURL))
    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: uri, type: .deleted)]))

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

    let markedFileContents = """
      import XCTest

      1️⃣class 2️⃣MyTests: XCTestCase {
        3️⃣func 4️⃣testSomething() {}5️⃣
      }6️⃣
      """

    let url = try XCTUnwrap(project.uri(for: "MyTests.swift").fileURL)
      .deletingLastPathComponent()
      .appendingPathComponent("MyNewTests.swift")
    let uri = DocumentURI(url)
    try extractMarkers(markedFileContents).textWithoutMarkers.write(to: url, atomically: true, encoding: .utf8)
    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: uri, type: .created)])
    )

    let positions = DocumentPositions(markedText: markedFileContents)

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["6️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testSomething()",
              label: "testSomething()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["5️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testInMemoryFileWithFallbackBuildSystem() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI.for(.swift)

    let positions = testClient.openDocument(
      """
      import XCTest

      1️⃣class 2️⃣MyTests: XCTestCase {
        3️⃣func 4️⃣testSomething() {}5️⃣
      }6️⃣
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
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["6️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testSomething()",
              label: "testSomething()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(uri: uri, range: positions["3️⃣"]..<positions["5️⃣"]),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testIndexedFileWithCompilationDbBuildSystem() async throws {
    try SkipUnless.longTestsEnabled()

    let project = try await IndexedSingleSwiftFileTestProject(
      """
      import XCTest

      class 1️⃣MyTests: XCTestCase {
        func 2️⃣testSomething() {}
      }
      """
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
          children: [
            TestItem(
              id: "MyTests/testSomething()",
              label: "testSomething()",
              disabled: false,
              style: TestStyle.xcTest,
              location: Location(uri: project.fileURI, range: Range(project.positions["2️⃣"])),
              children: [],
              tags: []
            )
          ],
          tags: []
        )
      ]
    )
  }

  func testOnDiskFileWithCompilationDbBuildSystem() async throws {
    let project = try await MultiFileTestProject(files: [
      "MyTests.swift": """
      import XCTest

      1️⃣class MyTests: XCTestCase {
        2️⃣func testSomething() {}3️⃣
      }4️⃣
      """,
      "compile_commands.json": "[]",
    ])

    // When MyTests.swift is not part of the compilation database, the build system doesn't know about the file and thus
    // doesn't return any tests for it.
    let testsWithEmptyCompilationDatabase = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(testsWithEmptyCompilationDatabase, [])

    let swiftc = try await unwrap(ToolchainRegistry.forTesting.default?.swiftc?.asURL)
    let uri = try project.uri(for: "MyTests.swift")

    let compilationDatabase = JSONCompilationDatabase([
      JSONCompilationDatabase.Command(
        directory: project.scratchDirectory.path,
        filename: uri.pseudoPath,
        commandLine: [swiftc.path, uri.pseudoPath]
      )
    ])

    try JSONEncoder()
      .encode(compilationDatabase).write(to: XCTUnwrap(project.uri(for: "compile_commands.json").fileURL))

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [
        FileEvent(uri: try project.uri(for: "compile_commands.json"), type: .changed)
      ])
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
          children: [
            TestItem(
              id: "MyTests/testSomething()",
              label: "testSomething()",
              disabled: false,
              style: TestStyle.xcTest,
              location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift"),
              children: [],
              tags: []
            )
          ],
          tags: []
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
        id: "MyTests",
        label: "MyTests",
        disabled: false,
        style: TestStyle.xcTest,
        location: try project.location(from: "1️⃣", to: "4️⃣", in: "MyTests.swift"),
        children: [
          TestItem(
            id: "MyTests/testMyLibrary()",
            label: "testMyLibrary()",
            disabled: false,
            style: TestStyle.xcTest,
            location: try project.location(from: "2️⃣", to: "3️⃣", in: "MyTests.swift"),
            children: [],
            tags: []
          )
        ],
        tags: []
      )
    ]

    let testsBeforeFileRemove = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(testsBeforeFileRemove, expectedTests)

    let myTestsUri = try project.uri(for: "MyTests.swift")
    let myTestsUrl = try XCTUnwrap(myTestsUri.fileURL)

    try FileManager.default.removeItem(at: myTestsUrl)
    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: myTestsUri, type: .deleted)]))

    let testsAfterFileRemove = try await project.testClient.send(WorkspaceTestsRequest())
    XCTAssertEqual(testsAfterFileRemove, [])

    try extractMarkers(markedFileContents).textWithoutMarkers.write(to: myTestsUrl, atomically: true, encoding: .utf8)
    project.testClient.send(DidChangeWatchedFilesNotification(changes: [FileEvent(uri: myTestsUri, type: .created)]))

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
        // swift-tools-version: 5.7

        import PackageDescription

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

    try (originalContents + addedTest).write(to: uri, atomically: true, encoding: .utf8)

    project.testClient.send(
      DidChangeWatchedFilesNotification(changes: [FileEvent(uri: project.fileURI, type: .changed)])
    )

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
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      build: true
    )

    let tests = try await project.testClient.send(WorkspaceTestsRequest())

    XCTAssertEqual(
      tests,
      [
        TestItem(
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: try project.location(from: "1️⃣", to: "1️⃣", in: "Test.m"),
          children: [
            TestItem(
              id: "MyTests/testSomething",
              label: "testSomething",
              disabled: false,
              style: TestStyle.xcTest,
              location: try project.location(from: "2️⃣", to: "2️⃣", in: "Test.m"),
              children: [],
              tags: []
            )
          ],
          tags: []
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
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [.testTarget(name: "MyLibraryTests")]
        )
        """,
      build: true
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
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.xcTest,
          location: Location(uri: uri, range: positions["1️⃣"]..<positions["4️⃣"]),
          children: [
            TestItem(
              id: "MyTests/testSomething",
              label: "testSomething",
              disabled: false,
              style: TestStyle.xcTest,
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
          id: "MyTests",
          label: "MyTests",
          disabled: false,
          style: TestStyle.swiftTesting,
          location: Location(uri: fileBURI, range: fileBPositions["1️⃣"]..<fileBPositions["2️⃣"]),
          children: [
            TestItem(
              id: "MyTests/inStruct()",
              label: "inStruct()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: fileBURI, range: fileBPositions["3️⃣"]..<fileBPositions["4️⃣"]),
              children: [],
              tags: []
            ),
            TestItem(
              id: "MyTests/inExtension()",
              label: "inExtension()",
              disabled: false,
              style: TestStyle.swiftTesting,
              location: Location(uri: fileAURI, range: fileAPositions["5️⃣"]..<fileAPositions["6️⃣"]),
              children: [],
              tags: []
            ),
          ],
          tags: []
        )
      ]
    )
  }
}
