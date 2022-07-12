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
import XCTest

final class CallHierarchyTests: XCTestCase {
  func testCallHierarchy() throws {
    let ws = try staticSourceKitTibsWorkspace(name: "CallHierarchy")!
    try ws.buildAndIndex()

    try ws.openDocument(ws.testLoc("a.swift").url, language: .swift)

    // Requests

    func callHierarchy(at testLoc: TestLocation) throws -> [CallHierarchyItem] {
      let textDocument = testLoc.docIdentifier
      let request = CallHierarchyPrepareRequest(textDocument: textDocument, position: Position(testLoc))
      let items = try ws.sk.sendSync(request)
      return items ?? []
    }

    func incomingCalls(at testLoc: TestLocation) throws -> [CallHierarchyIncomingCall] {
      guard let item = try callHierarchy(at: testLoc).first else {
        fatalError("Call hierarchy at \(testLoc) was empty")
      }
      let request = CallHierarchyIncomingCallsRequest(item: item)
      let calls = try ws.sk.sendSync(request)
      return calls ?? []
    }

    func outgoingCalls(at testLoc: TestLocation) throws -> [CallHierarchyOutgoingCall] {
      guard let item = try callHierarchy(at: testLoc).first else {
        fatalError("Call hierarchy at \(testLoc) was empty")
      }
      let request = CallHierarchyOutgoingCallsRequest(item: item)
      let calls = try ws.sk.sendSync(request)
      return calls ?? []
    }

    func usr(at testLoc: TestLocation) throws -> String {
      guard let item = try callHierarchy(at: testLoc).first else {
        fatalError("Call hierarchy at \(testLoc) was empty")
      }
      guard case let .dictionary(data) = item.data,
            case let .string(usr) = data["usr"] else {
        fatalError("Could not find usr in call hierarchy item data dict")
      }
      return usr
    }

    // Convenience functions

    func testLoc(_ name: String) -> TestLocation {
      ws.testLoc(name)
    }  

    func loc(_ name: String) -> Location {
      Location(badUTF16: ws.testLoc(name))
    }

    func item(_ name: String, _ kind: SymbolKind, detail: String = "main", usr: String, at locName: String) -> CallHierarchyItem {
      let location = loc(locName)
      return CallHierarchyItem(
        name: name,
        kind: kind,
        tags: nil,
        detail: detail,
        uri: location.uri,
        range: location.range,
        selectionRange: location.range,
        data: .dictionary([
          "usr": .string(usr),
          "uri": .string(location.uri.stringValue)
        ])
      )
    }

    func inCall(_ item: CallHierarchyItem, at locName: String) -> CallHierarchyIncomingCall {
      CallHierarchyIncomingCall(
        from: item,
        fromRanges: [loc(locName).range]
      )
    }

    func outCall(_ item: CallHierarchyItem, at locName: String) -> CallHierarchyOutgoingCall {
      CallHierarchyOutgoingCall(
        to: item,
        fromRanges: [loc(locName).range]
      )
    }

    let aUsr = try usr(at: testLoc("a"))
    let bUsr = try usr(at: testLoc("b"))
    let cUsr = try usr(at: testLoc("c"))
    let dUsr = try usr(at: testLoc("d"))

    // Test outgoing call hierarchy

    XCTAssertEqual(try outgoingCalls(at: testLoc("a")), [])
    XCTAssertEqual(try outgoingCalls(at: testLoc("b")), [
      outCall(item("a()", .function, usr: aUsr, at: "a"), at: "b->a"),
      outCall(item("c()", .function, usr: cUsr, at: "c"), at: "b->c"),
      outCall(item("b(x:)", .function, usr: bUsr, at: "b"), at: "b->b"),
    ])
    XCTAssertEqual(try outgoingCalls(at: testLoc("c")), [
      outCall(item("a()", .function, usr: aUsr, at: "a"), at: "c->a"),
      outCall(item("d()", .function, usr: dUsr, at: "d"), at: "c->d"),
      outCall(item("c()", .function, usr: cUsr, at: "c"), at: "c->c"),
    ])

    // Test incoming call hierarchy

    XCTAssertEqual(try incomingCalls(at: testLoc("a")), [
      inCall(item("b(x:)", .function, usr: bUsr, at: "b"), at: "b->a"),
      inCall(item("c()", .function, usr: cUsr, at: "c"), at: "c->a"),
    ])
    XCTAssertEqual(try incomingCalls(at: testLoc("b")), [
      inCall(item("b(x:)", .function, usr: bUsr, at: "b"), at: "b->b"),
    ])
    XCTAssertEqual(try incomingCalls(at: testLoc("d")), [
      inCall(item("c()", .function, usr: cUsr, at: "c"), at: "c->d"),
    ])
  }
}
