//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ISDBTestSupport
import LanguageServerProtocol
import SKTestSupport
import TSCBasic
import XCTest

final class TypeHierarchyTests: XCTestCase {
  func testRootClassSupertypes() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      class 1️⃣MyClass {}
      """
    )

    let item = try await ws.prepareTypeHierarchy(at: "1️⃣")
    let supertypes = try await ws.testClient.send(TypeHierarchySupertypesRequest(item: item))
    assertEqualIgnoringData(supertypes, [])
  }

  func testSupertypesOfClass() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      class 1️⃣MyClass {}
      protocol 2️⃣MyProtocol {}
      class 3️⃣MySubclass: MyClass, MyProtocol {}
      """
    )

    let item = try await ws.prepareTypeHierarchy(at: "3️⃣")
    let supertypes = try await ws.testClient.send(TypeHierarchySupertypesRequest(item: item))
    assertEqualIgnoringData(
      supertypes,
      [
        TypeHierarchyItem(name: "MyClass", kind: .class, location: "1️⃣", in: ws),
        TypeHierarchyItem(name: "MyProtocol", kind: .interface, location: "2️⃣", in: ws),
      ]
    )
  }

  func testConformedProtocolsOfStruct() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      protocol 1️⃣MyProtocol {}
      protocol 2️⃣MyOtherProtocol {}
      struct 3️⃣MyStruct: MyProtocol {}
      extension MyStruct: MyOtherProtocol {}
      """
    )

    let item = try await ws.prepareTypeHierarchy(at: "3️⃣")
    let supertypes = try await ws.testClient.send(TypeHierarchySupertypesRequest(item: item))
    assertEqualIgnoringData(
      supertypes,
      [
        TypeHierarchyItem(name: "MyProtocol", kind: .interface, location: "1️⃣", in: ws),
        TypeHierarchyItem(name: "MyOtherProtocol", kind: .interface, location: "2️⃣", in: ws),
      ]
    )
  }

  func testSubtypesOfClass() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      class MySuperclass {}
      class 1️⃣MyClass: MySuperclass {}
      class 2️⃣SubclassA: MyClass {}
      class 3️⃣SubclassB: MyClass {}
      """
    )

    let item = try await ws.prepareTypeHierarchy(at: "1️⃣")
    let subtypes = try await ws.testClient.send(TypeHierarchySubtypesRequest(item: item))
    assertEqualIgnoringData(
      subtypes,
      [
        TypeHierarchyItem(name: "SubclassA", kind: .class, location: "2️⃣", in: ws),
        TypeHierarchyItem(name: "SubclassB", kind: .class, location: "3️⃣", in: ws),
      ]
    )
  }

  func testProtocolConformancesAsSubtypes() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      protocol 1️⃣MyProtocol {}
      class 2️⃣MyClass: MyProtocol {}
      struct 3️⃣MyStruct: MyProtocol {}
      enum 4️⃣MyEnum: MyProtocol {}
      """
    )

    let item = try await ws.prepareTypeHierarchy(at: "1️⃣")
    let subtypes = try await ws.testClient.send(TypeHierarchySubtypesRequest(item: item))
    assertEqualIgnoringData(
      subtypes,
      [
        TypeHierarchyItem(name: "MyClass", kind: .class, location: "2️⃣", in: ws),
        TypeHierarchyItem(name: "MyStruct", kind: .struct, location: "3️⃣", in: ws),
        TypeHierarchyItem(name: "MyEnum", kind: .enum, location: "4️⃣", in: ws),
      ]
    )
  }

  func testExtensionsWithConformancesAsSubtypes() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      protocol MyProtocol {}
      enum 1️⃣MyEnum {}
      extension 2️⃣MyEnum {
        func foo() {}
      }
      extension 3️⃣MyEnum: MyProtocol {}
      """
    )

    let item = try await ws.prepareTypeHierarchy(at: "1️⃣")
    let subtypes = try await ws.testClient.send(TypeHierarchySubtypesRequest(item: item))
    assertEqualIgnoringData(
      subtypes,
      [
        TypeHierarchyItem(name: "MyEnum", kind: .null, detail: "Extension at test.swift:3", location: "2️⃣", in: ws),
        TypeHierarchyItem(
          name: "MyEnum: MyProtocol",
          kind: .null,
          detail: "Extension at test.swift:6",
          location: "3️⃣",
          in: ws
        ),
      ]
    )
  }

  func testRetroactiveConformancesAsSubtypes() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      protocol 1️⃣MyProtocol {}
      struct MyStruct {}
      extension 2️⃣MyStruct: MyProtocol {}
      """
    )

    let item = try await ws.prepareTypeHierarchy(at: "1️⃣")
    let subtypes = try await ws.testClient.send(TypeHierarchySubtypesRequest(item: item))
    assertEqualIgnoringData(
      subtypes,
      [
        TypeHierarchyItem(
          name: "MyStruct: MyProtocol",
          kind: .null,
          detail: "Extension at test.swift:3",
          location: "2️⃣",
          in: ws
        )
      ]
    )
  }

  func testSupertypesFromCall() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      class 1️⃣MyClass {}
      class MySubclass: MyClass {}

      let x = 2️⃣MySubclass()
      """
    )
    let item = try await ws.prepareTypeHierarchy(at: "2️⃣")
    let supertypes = try await ws.testClient.send(TypeHierarchySupertypesRequest(item: item))
    assertEqualIgnoringData(
      supertypes,
      [
        TypeHierarchyItem(name: "MyClass", kind: .class, location: "1️⃣", in: ws)
      ]
    )
  }
}

// MARK: - Utilities

fileprivate extension TypeHierarchyItem {
  var withoutData: TypeHierarchyItem {
    var item = self
    item.data = nil
    return item
  }
}

/// Compares the given type hierarchies ignoring the implementation-specific
/// data field (which includes e.g. USRs that are difficult to test, especially
/// in the presence of extensions, and are not user-visible anyway).
fileprivate func assertEqualIgnoringData(
  _ actual: [TypeHierarchyItem]?,
  _ expected: [TypeHierarchyItem],
  file: StaticString = #file,
  line: UInt = #line
) {
  guard let actual else {
    XCTFail("Expected non-nil type hierarchy", file: file, line: line)
    return
  }
  XCTAssertEqual(
    actual.map(\.withoutData),
    expected.map(\.withoutData),
    file: file,
    line: line
  )
}

fileprivate extension TypeHierarchyItem {
  init(
    name: String,
    kind: SymbolKind,
    detail: String = "test",
    location locationMarker: String,
    in ws: IndexedSingleSwiftFileWorkspace
  ) {
    self.init(
      name: name,
      kind: kind,
      tags: nil,
      detail: detail,
      uri: ws.fileURI,
      range: Range(ws.positions[locationMarker]),
      selectionRange: Range(ws.positions[locationMarker])
    )
  }
}

fileprivate extension IndexedSingleSwiftFileWorkspace {
  func prepareTypeHierarchy(at locationMarker: String, line: UInt = #line) async throws -> TypeHierarchyItem {
    let items = try await testClient.send(
      TypeHierarchyPrepareRequest(
        textDocument: TextDocumentIdentifier(self.fileURI),
        position: self.positions[locationMarker]
      )
    )
    XCTAssertEqual(items?.count, 1, "Expected exactly one item from the type hierarchy preapre", line: line)
    return try XCTUnwrap(items?.first, line: line)
  }
}
