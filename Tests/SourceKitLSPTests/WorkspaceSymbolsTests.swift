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
import XCTest

class WorkspaceSymbolsTests: SourceKitLSPTestCase {
  func testWorkspaceSymbolsAcrossPackages() async throws {
    let project = try await MultiFileTestProject(
      files: [
        "packageA/Sources/PackageALib/PackageALib.swift": """
        public func 1️⃣afuncFromA() {}
        """,
        "packageA/Package.swift": """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "PackageA",
          products: [
            .library(name: "PackageALib", targets: ["PackageALib"])
          ],
          targets: [
            .target(name: "PackageALib"),
          ]
        )
        """,
        "packageB/Sources/PackageBLib/PackageBLib.swift": """
        public func 2️⃣funcFromB() {}
        """,
        "packageB/Package.swift": """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "PackageB",
          dependencies: [
            .package(path: "../packageA"),
          ],
          targets: [
            .target(
              name: "PackageBLib",
              dependencies: [.product(name: "PackageALib", package: "PackageA")]
            ),
          ]
        )
        """,
      ],
      workspaces: {
        return [WorkspaceFolder(uri: DocumentURI($0.appending(component: "packageB")))]
      },
      enableBackgroundIndexing: true
    )

    try await project.testClient.send(SynchronizeRequest(index: true))
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "funcFrom"))

    // Ideally, the item from the current package (PackageB) should be returned before the item from PackageA
    // https://github.com/swiftlang/sourcekit-lsp/issues/1094
    XCTAssertEqual(
      response,
      [
        .symbolInformation(
          SymbolInformation(
            name: "afuncFromA()",
            kind: .function,
            location: try project.location(from: "1️⃣", to: "1️⃣", in: "PackageALib.swift")
          )
        ),
        .symbolInformation(
          SymbolInformation(
            name: "funcFromB()",
            kind: .function,
            location: try project.location(from: "2️⃣", to: "2️⃣", in: "PackageBLib.swift")
          )
        ),
      ]
    )
  }

  func testContainerNameOfFunctionInExtension() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Foo {
        struct Bar {}
      }

      extension Foo.Bar {
        func 1️⃣barMethod() {}
      }
      """
    )
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "barMethod"))
    XCTAssertEqual(
      response,
      [
        .symbolInformation(
          SymbolInformation(
            name: "barMethod()",
            kind: .method,
            location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
            containerName: "Foo.Bar"
          )
        )
      ]
    )
  }

  func testHideSymbolsFromExcludedFiles() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "FileA.swift": "func 1️⃣doThingA() {}",
        "FileB.swift": "func 2️⃣doThingB() {}",
      ],
      manifest: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [.target(name: "MyLibrary")]
        )
        """,
      enableBackgroundIndexing: true
    )
    let symbolsBeforeDeletion = try await project.testClient.send(WorkspaceSymbolsRequest(query: "doThing"))
    XCTAssertEqual(
      symbolsBeforeDeletion,
      [
        .symbolInformation(
          SymbolInformation(
            name: "doThingA()",
            kind: .function,
            location: try project.location(from: "1️⃣", to: "1️⃣", in: "FileA.swift")
          )
        ),
        .symbolInformation(
          SymbolInformation(
            name: "doThingB()",
            kind: .function,
            location: try project.location(from: "2️⃣", to: "2️⃣", in: "FileB.swift")
          )
        ),
      ]
    )

    try await project.changeFileOnDisk(
      "Package.swift",
      newMarkedContents: """
        // swift-tools-version: 5.7

        import PackageDescription

        let package = Package(
          name: "MyLibrary",
          targets: [.target(name: "MyLibrary", exclude: ["FileA.swift"])]
        )
        """
    )

    try await repeatUntilExpectedResult {
      let symbolsAfterDeletion = try await project.testClient.send(WorkspaceSymbolsRequest(query: "doThing"))
      if symbolsAfterDeletion?.count == 2 {
        // The exclusion hasn't been processed yet, try again.
        return false
      }
      XCTAssertEqual(
        symbolsAfterDeletion,
        [
          .symbolInformation(
            SymbolInformation(
              name: "doThingB()",
              kind: .function,
              location: try project.location(from: "2️⃣", to: "2️⃣", in: "FileB.swift")
            )
          )
        ]
      )
      return true
    }
  }

  func testQualifiedWorkspaceSymbolMatchesMemberAndParent() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Foo {
        func 1️⃣bar() {}
      }

      struct Baz {
        func bar() {}
      }
      """
    )
    let expected: [WorkspaceSymbolItem] = [
      .symbolInformation(
        SymbolInformation(
          name: "Foo.bar()",
          kind: .method,
          location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))
        )
      )
    ]

    // Only `Foo`'s member matches; `Baz.bar` is excluded because its container isn't `Foo`.
    let dotSeparator = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Foo.bar"))
    XCTAssertEqual(dotSeparator, expected)

    // `::` is accepted as a separator too. The symbol is Swift, so the qualified label still uses the
    // Swift `.` separator.
    let colonSeparator = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Foo::bar"))
    XCTAssertEqual(colonSeparator, expected)
  }

  func testQualifiedWorkspaceSymbolMatchesExtensionMember() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Foo {}

      extension Foo {
        func 1️⃣bar() {}
      }
      """
    )
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Foo.bar"))
    XCTAssertEqual(
      response,
      [
        .symbolInformation(
          SymbolInformation(
            name: "Foo.bar()",
            kind: .method,
            location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))
          )
        )
      ]
    )
  }

  func testQualifiedWorkspaceSymbolMatchesTypeInExtensionOfNestedType() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      enum Namespace {
        enum Sub {}
      }

      extension Namespace.Sub {
        struct 1️⃣Foo {}
      }
      """
    )
    // `Foo` is `childOf` an extension of the nested type `Namespace.Sub`. Resolving the `Namespace.Sub`
    // container (verifying `Sub`'s ancestor is `Namespace`) and then reaching `Foo` through that
    // extension must still find it.
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Namespace.Sub.Foo"))
    assertContains(
      response ?? [],
      .symbolInformation(
        SymbolInformation(
          name: "Namespace.Sub.Foo",
          kind: .struct,
          location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))
        )
      )
    )
  }

  func testQualifiedWorkspaceSymbolMatchesMemberOfTypeInExtensionOfNestedType() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      enum Namespace {
        enum Sub {}
      }

      extension Namespace.Sub {
        struct Foo {
          var 1️⃣bar: Int
        }
      }
      """
    )
    // `Foo` is `childOf` the extension of the nested type `Namespace.Sub`, so verifying the ancestors of
    // the `Namespace.Sub.Foo` container has to climb from the extension to the extended type `Sub` (which
    // is where the `childOf Namespace` link lives). Use `contains` because the query also matches the
    // synthesized memberwise `init(bar:)`.
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Namespace.Sub.Foo.bar"))
    assertContains(
      response ?? [],
      .symbolInformation(
        SymbolInformation(
          name: "Namespace.Sub.Foo.bar",
          kind: .property,
          location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))
        )
      )
    )
  }

  func testQualifiedWorkspaceSymbolMatchesMemberOfNestedTypeInExtension() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      enum Namespace {}

      extension Namespace {
        struct Foo {
          var 1️⃣bar: Int
        }
      }
      """
    )
    // `Foo` is `childOf` an extension of `Namespace`, so resolving the `Namespace.Foo` container has to
    // match `Foo`'s enclosing extension by name. Use `contains` because the query also matches the
    // synthesized memberwise `init(bar:)`.
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Namespace.Foo.bar"))
    assertContains(
      response ?? [],
      .symbolInformation(
        SymbolInformation(
          name: "Namespace.Foo.bar",
          kind: .property,
          location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))
        )
      )
    )
  }

  func testQualifiedWorkspaceSymbolFuzzyMemberMatch() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Foo {
        func 1️⃣longMethodName() {}
      }
      """
    )
    // `lmn` is a non-contiguous subsequence of `longMethodName`, exercising the fuzzy member match.
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Foo.lmn"))
    XCTAssertEqual(
      response,
      [
        .symbolInformation(
          SymbolInformation(
            name: "Foo.longMethodName()",
            kind: .method,
            location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))
          )
        )
      ]
    )
  }

  func testQualifiedWorkspaceSymbolWithWrongParentReturnsNothing() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Foo {
        func bar() {}
      }
      """
    )
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Quux.bar"))
    XCTAssertEqual(response, [])
  }

  func testQualifiedWorkspaceSymbolMultiLevelChain() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Outer {
        struct Inner {
          func 1️⃣method() {}
        }
      }

      struct Other {
        func method() {}
      }
      """
    )
    let expected: [WorkspaceSymbolItem] = [
      .symbolInformation(
        SymbolInformation(
          name: "Outer.Inner.method()",
          kind: .method,
          location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))
        )
      )
    ]

    // The full chain matches by walking `Inner`'s enclosing scopes up to `Outer`.
    let fullChain = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Outer.Inner.method"))
    XCTAssertEqual(fullChain, expected)

    // The nested `Inner` is also resolved by its simple name without naming `Outer`; `Other.method` must
    // not match since its container isn't `Inner`.
    let innermostOnly = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Inner.method"))
    XCTAssertEqual(innermostOnly, expected)
  }

  func testQualifiedWorkspaceSymbolReturnsSystemMembersAsGeneratedInterface() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      let x: String = ""
      """,
      capabilities: ClientCapabilities(
        workspace: .init(symbol: .init(resolveSupport: .init(properties: ["location"]))),
        experimental: [GetReferenceDocumentRequest.method: .dictionary(["supported": .bool(true)])]
      ),
      indexSystemModules: true
    )
    // A qualified query into a stdlib type returns its members as `sourcekit-lsp://generated-swift-interface`
    // reference-document symbols when the client can open them.
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "String."))
    let generatedInterfaceMembers = (response ?? []).filter { item in
      guard case .workspaceSymbol(let symbol) = item,
        case .uri(let uriOnly) = symbol.location,
        let components = URLComponents(string: uriOnly.uri.arbitrarySchemeURL.absoluteString)
      else {
        return false
      }
      return components.scheme == "sourcekit-lsp" && components.host == "generated-swift-interface"
        && symbol.name.contains("String")
    }
    XCTAssertFalse(
      generatedInterfaceMembers.isEmpty,
      "Expected `String` members as generated-interface reference documents, got \(String(describing: response))"
    )
  }

  func testQualifiedWorkspaceSymbolOmitsSystemMembersWithoutGeneratedInterfaceSupport() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      let x: String = ""
      """,
      indexSystemModules: true
    )
    // Without generated-interface support the client can't navigate to system members, so a qualified query
    // into a stdlib type returns nothing rather than un-navigable `file://` results.
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "String."))
    XCTAssertEqual(response, [])
  }

  func testQualifiedWorkspaceSymbolMatchesUserExtensionOfSystemTypeWithoutGeneratedInterfaceSupport()
    async throws
  {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      extension String {
        struct Inner { var 1️⃣member: Int }
        var 2️⃣isBlank: Bool { false }
      }
      """,
      indexSystemModules: true
    )
    // The client can't open generated interfaces, so stdlib members of `String` are excluded. Members the
    // user declared in their own `extension String` are still in their own source and remain navigable, so
    // they are returned with a plain `file://` location.
    let members = try await project.testClient.send(WorkspaceSymbolsRequest(query: "String."))
    let memberNames = (members ?? []).compactMap { item -> String? in
      guard case .symbolInformation(let info) = item else { return nil }
      return info.name
    }
    XCTAssertEqual(memberNames.sorted(), ["String.Inner", "String.isBlank"])

    assertContains(
      members ?? [],
      .symbolInformation(
        SymbolInformation(
          name: "String.isBlank",
          kind: .property,
          location: Location(uri: project.fileURI, range: Range(project.positions["2️⃣"]))
        )
      )
    )

    // A type nested in the user's extension of a system type is itself non-system, so its members are
    // returned both through the full chain and by the nested type's simple name.
    for query in ["String.Inner.member", "Inner.member"] {
      let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: query))
      assertContains(
        response ?? [],
        .symbolInformation(
          SymbolInformation(
            name: "String.Inner.member",
            kind: .property,
            location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"]))
          )
        )
      )
    }
  }

  func testQualifiedWorkspaceSymbolMatchesCXXMemberDefinedOutOfLine() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/include/lib.h": """
        struct FilePathIndex {
          void foo();
          void foo(int x);
        };
        """,
        "MyLibrary/lib.cpp": """
        #include "lib.h"
        void FilePathIndex::1️⃣foo() {}
        void FilePathIndex::2️⃣foo(int x) {}
        """,
      ],
      enableBackgroundIndexing: true
    )
    // The overloads of `foo` are declared in the header and defined out-of-line in the `.cpp`. Both are
    // returned, each pointing at its definition in the `.cpp`.
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "FilePathIndex::foo"))
    assertContains(
      response ?? [],
      .symbolInformation(
        SymbolInformation(
          name: "FilePathIndex::foo",
          kind: .method,
          location: Location(
            uri: try project.uri(for: "lib.cpp"),
            range: try Range(project.position(of: "1️⃣", in: "lib.cpp"))
          )
        )
      )
    )
    assertContains(
      response ?? [],
      .symbolInformation(
        SymbolInformation(
          name: "FilePathIndex::foo",
          kind: .method,
          location: Location(
            uri: try project.uri(for: "lib.cpp"),
            range: try Range(project.position(of: "2️⃣", in: "lib.cpp"))
          )
        )
      )
    )
  }

  func testQualifiedWorkspaceSymbolMatchesCXXMemberInNamespace() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "MyLibrary/include/lib.h": """
        namespace mynamespace {
          void foo();
          struct MyStruct {
            void bar();
          };
        }
        """,
        "MyLibrary/lib.cpp": """
        #include "lib.h"
        namespace mynamespace {
          void 1️⃣foo() {}
          void MyStruct::2️⃣bar() {}
        }
        """,
      ],
      enableBackgroundIndexing: true
    )
    // `foo` is scoped to the C++ namespace `mynamespace`; the qualified query resolves it through the
    // namespace and returns its out-of-line definition in the `.cpp`.
    let namespaceResponse = try await project.testClient.send(WorkspaceSymbolsRequest(query: "mynamespace::foo"))
    assertContains(
      namespaceResponse ?? [],
      .symbolInformation(
        SymbolInformation(
          name: "mynamespace::foo",
          kind: .function,
          location: Location(
            uri: try project.uri(for: "lib.cpp"),
            range: try Range(project.position(of: "1️⃣", in: "lib.cpp"))
          )
        )
      )
    )
    // A method of a struct nested in the namespace is reached through the full `namespace::type::member`
    // chain.
    let nestedResponse = try await project.testClient.send(
      WorkspaceSymbolsRequest(query: "mynamespace::MyStruct::bar")
    )
    assertContains(
      nestedResponse ?? [],
      .symbolInformation(
        SymbolInformation(
          name: "mynamespace::MyStruct::bar",
          kind: .method,
          location: Location(
            uri: try project.uri(for: "lib.cpp"),
            range: try Range(project.position(of: "2️⃣", in: "lib.cpp"))
          )
        )
      )
    )
    // The struct can also be resolved by its simple name without naming the enclosing namespace.
    let innermostResponse = try await project.testClient.send(WorkspaceSymbolsRequest(query: "MyStruct::bar"))
    assertContains(
      innermostResponse ?? [],
      .symbolInformation(
        SymbolInformation(
          name: "mynamespace::MyStruct::bar",
          kind: .method,
          location: Location(
            uri: try project.uri(for: "lib.cpp"),
            range: try Range(project.position(of: "2️⃣", in: "lib.cpp"))
          )
        )
      )
    )
  }

  func testQualifiedWorkspaceSymbolListsAllMembersWithTrailingSeparator() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Foo {
        func bar() {}
        var baz: Int { 0 }
      }

      struct Other {
        func qux() {}
      }
      """
    )
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Foo."))
    let names = (response ?? []).compactMap { item -> String? in
      guard case .symbolInformation(let info) = item else { return nil }
      return info.name
    }
    // All of `Foo`'s members are listed with their qualified name, and members of other types are not.
    assertContains(names, "Foo.bar()")
    assertContains(names, "Foo.baz")
    XCTAssertFalse(names.contains(where: { $0.contains("qux") }), "\(names)")
  }

  func testQualifiedWorkspaceSymbolMultiLevelChainRejectsWrongOuter() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Outer {
        struct Inner {
          func method() {}
        }
      }
      """
    )
    let response = try await project.testClient.send(WorkspaceSymbolsRequest(query: "Wrong.Inner.method"))
    XCTAssertEqual(response, [])
  }
}
