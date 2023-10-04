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
import TSCBasic
import XCTest

final class TypeHierarchyTests: XCTestCase {
  func testTypeHierarchy() async throws {
    let ws = try await staticSourceKitTibsWorkspace(name: "TypeHierarchy")!
    try ws.buildAndIndex()

    try ws.openDocument(ws.testLoc("a.swift").url, language: .swift)

    // Requests

    func typeHierarchy(at testLoc: TestLocation) throws -> [TypeHierarchyItem] {
      let textDocument = testLoc.docIdentifier
      let request = TypeHierarchyPrepareRequest(textDocument: textDocument, position: Position(testLoc))
      let items = try ws.sk.sendSync(request)
      return items ?? []
    }

    func supertypes(at testLoc: TestLocation) throws -> [TypeHierarchyItem] {
      guard let item = try typeHierarchy(at: testLoc).first else {
        XCTFail("Type hierarchy at \(testLoc) was empty")
        return []
      }
      let request = TypeHierarchySupertypesRequest(item: item)
      let types = try ws.sk.sendSync(request)
      return types ?? []
    }

    func subtypes(at testLoc: TestLocation) throws -> [TypeHierarchyItem] {
      guard let item = try typeHierarchy(at: testLoc).first else {
        XCTFail("Type hierarchy at \(testLoc) was empty")
        return []
      }
      let request = TypeHierarchySubtypesRequest(item: item)
      let types = try ws.sk.sendSync(request)
      return types ?? []
    }

    // Convenience functions

    func testLoc(_ name: String) -> TestLocation {
      ws.testLoc(name)
    }  

    func loc(_ name: String) -> Location {
      Location(badUTF16: ws.testLoc(name))
    }

    func withoutData(_ item: TypeHierarchyItem) -> TypeHierarchyItem {
      var item = item
      item.data = nil
      return item
    }

    /// Compares the given type hierarchies ignoring the implementation-specific
    /// data field (which includes e.g. USRs that are difficult to test, especially
    /// in the presence of extensions, and are not user-visible anyway).
    func assertEqualIgnoringData(
      _ actual: [TypeHierarchyItem],
      _ expected: [TypeHierarchyItem],
      file: StaticString = #file,
      line: UInt = #line
    ) {
      XCTAssertEqual(
        actual.map(withoutData),
        expected.map(withoutData),
        file: file,
        line: line
      )
    }

    func item(_ name: String, _ kind: SymbolKind, detail: String = "main", at locName: String) throws -> TypeHierarchyItem {
      let location = loc(locName)
      return TypeHierarchyItem(
        name: name,
        kind: kind,
        tags: nil,
        detail: detail,
        uri: try location.uri.nativeURI,
        range: location.range,
        selectionRange: location.range
      )
    }

    // Test type hierarchy preparation

    assertEqualIgnoringData(try typeHierarchy(at: testLoc("P")), [
      try item("P", .interface, at: "P"),
    ])
    assertEqualIgnoringData(try typeHierarchy(at: testLoc("A")), [
      try item("A", .class, at: "A"),
    ])
    assertEqualIgnoringData(try typeHierarchy(at: testLoc("S")), [
      try item("S", .struct, at: "S"),
    ])
    assertEqualIgnoringData(try typeHierarchy(at: testLoc("E")), [
      try item("E", .enum, at: "E"),
    ])

    // Test supertype hierarchy

    assertEqualIgnoringData(try supertypes(at: testLoc("A")), [])
    assertEqualIgnoringData(try supertypes(at: testLoc("B")), [
      try item("A", .class, at: "A"),
      try item("P", .interface, at: "P"),
    ])
    assertEqualIgnoringData(try supertypes(at: testLoc("C")), [
      try item("B", .class, at: "B"),
    ])
    assertEqualIgnoringData(try supertypes(at: testLoc("D")), [
      try item("A", .class, at: "A"),
    ])
    assertEqualIgnoringData(try supertypes(at: testLoc("S")), [
      try item("P", .interface, at: "P"),
      try item("X", .interface, at: "X"), // Retroactive conformance
    ])
    assertEqualIgnoringData(try supertypes(at: testLoc("E")), [
      try item("P", .interface, at: "P"),
      try item("Y", .interface, at: "Y"), // Retroactive conformance
      try item("Z", .interface, at: "Z"), // Retroactive conformance
    ])

    // Test subtype hierarchy (includes extensions)

    assertEqualIgnoringData(try subtypes(at: testLoc("A")), [
      try item("B", .class, at: "B"),
      try item("D", .class, at: "D"),
    ])
    assertEqualIgnoringData(try subtypes(at: testLoc("B")), [
      try item("C", .class, at: "C"),
    ])
    assertEqualIgnoringData(try subtypes(at: testLoc("P")), [
      try item("B", .class, at: "B"),
      try item("S", .struct, at: "S"),
      try item("E", .enum, at: "E"),
    ])
    assertEqualIgnoringData(try subtypes(at: testLoc("E")), [
      try item("E: Y, Z", .null, detail: "Extension at a.swift:19", at: "extE:Y,Z"),
    ])
    assertEqualIgnoringData(try subtypes(at: testLoc("S")), [
      try item("S: X", .null, detail: "Extension at a.swift:15", at: "extS:X"),
      try item("S", .null, detail: "Extension at a.swift:16", at: "extS"),
    ])
    assertEqualIgnoringData(try subtypes(at: testLoc("X")), [
      try item("S: X", .null, detail: "Extension at a.swift:15", at: "extS:X"),
    ])
    assertEqualIgnoringData(try subtypes(at: testLoc("Y")), [
      try item("E: Y, Z", .null, detail: "Extension at a.swift:19", at: "extE:Y,Z"),
    ])
    assertEqualIgnoringData(try subtypes(at: testLoc("Z")), [
      try item("E: Y, Z", .null, detail: "Extension at a.swift:19", at: "extE:Y,Z"),
    ])

    // Ensure that type hierarchies can be fetched from uses too

    for name in ["A", "S"] {
      for occurrence in ["type", "init"] {
        let declLoc = testLoc(name)
        let occurLoc = testLoc(occurrence + name)

        try assertEqualIgnoringData(typeHierarchy(at: occurLoc), typeHierarchy(at: declLoc))
        try assertEqualIgnoringData(supertypes(at: occurLoc), supertypes(at: declLoc))
        try assertEqualIgnoringData(subtypes(at: occurLoc), subtypes(at: declLoc))
      }
    }
  }
}
