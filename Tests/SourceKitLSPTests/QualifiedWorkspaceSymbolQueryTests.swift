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

@_spi(Testing) import SourceKitLSP
import XCTest

final class QualifiedWorkspaceSymbolQueryTests: XCTestCase {
  func testUnqualifiedQueriesReturnNil() {
    XCTAssertNil(QualifiedWorkspaceSymbolQuery("description"))
    XCTAssertNil(QualifiedWorkspaceSymbolQuery("foo123_bar"))
    XCTAssertNil(QualifiedWorkspaceSymbolQuery(""))
  }

  func testDotSeparator() {
    let q = QualifiedWorkspaceSymbolQuery("String.description")
    XCTAssertEqual(q?.containerChain, ["String"])
    XCTAssertEqual(q?.member, "description")
  }

  func testColonColonSeparator() {
    let q = QualifiedWorkspaceSymbolQuery("Foo::bar")
    XCTAssertEqual(q?.containerChain, ["Foo"])
    XCTAssertEqual(q?.member, "bar")
  }

  func testMultiLevelDotChain() {
    let q = QualifiedWorkspaceSymbolQuery("Outer.Inner.method")
    XCTAssertEqual(q?.containerChain, ["Outer", "Inner"])
    XCTAssertEqual(q?.member, "method")
  }

  func testMultiLevelColonChain() {
    let q = QualifiedWorkspaceSymbolQuery("Outer::Inner::method")
    XCTAssertEqual(q?.containerChain, ["Outer", "Inner"])
    XCTAssertEqual(q?.member, "method")
  }

  func testMixedSeparators() {
    let q = QualifiedWorkspaceSymbolQuery("Outer::Inner.method")
    XCTAssertEqual(q?.containerChain, ["Outer", "Inner"])
    XCTAssertEqual(q?.member, "method")
  }

  func testTrailingSeparatorListsAllMembers() {
    // A trailing separator with an empty member is a valid qualified query that lists all members of
    // the container.
    let dot = QualifiedWorkspaceSymbolQuery("Foo.")
    XCTAssertEqual(dot?.containerChain, ["Foo"])
    XCTAssertEqual(dot?.member, "")

    let colon = QualifiedWorkspaceSymbolQuery("Foo::")
    XCTAssertEqual(colon?.containerChain, ["Foo"])
    XCTAssertEqual(colon?.member, "")

    let nested = QualifiedWorkspaceSymbolQuery("Outer.Inner.")
    XCTAssertEqual(nested?.containerChain, ["Outer", "Inner"])
    XCTAssertEqual(nested?.member, "")
  }

  func testLeadingSeparatorRejected() {
    XCTAssertNil(QualifiedWorkspaceSymbolQuery(".bar"))
    XCTAssertNil(QualifiedWorkspaceSymbolQuery("::bar"))
  }

  func testLoneColonRejected() {
    // A single `:` isn't a qualifier separator; it's a literal character. `Foo:bar` therefore has no
    // separator at all and is not a qualified query, so the parser returns `nil`.
    XCTAssertNil(QualifiedWorkspaceSymbolQuery("Foo:bar"))
  }

  func testArgumentLabelColonsArePartOfMember() {
    // A lone `:` is a literal, so Swift argument labels survive in the member component.
    let dotQuery = QualifiedWorkspaceSymbolQuery("Collection.append(contentsOf:)")
    XCTAssertEqual(dotQuery?.containerChain, ["Collection"])
    XCTAssertEqual(dotQuery?.member, "append(contentsOf:)")

    // `::` still separates even when the member carries argument-label colons.
    let colonQuery = QualifiedWorkspaceSymbolQuery("Foo::subscript(at:)")
    XCTAssertEqual(colonQuery?.containerChain, ["Foo"])
    XCTAssertEqual(colonQuery?.member, "subscript(at:)")
  }

  func testEmptyParentSegmentRejected() {
    XCTAssertNil(QualifiedWorkspaceSymbolQuery("Foo..bar"))
    XCTAssertNil(QualifiedWorkspaceSymbolQuery("Foo.::bar"))
  }
}
