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
import LSPTestSupport
import LanguageServerProtocol
import SKTestSupport
import TSCBasic
import XCTest

final class CallHierarchyTests: XCTestCase {
  func testCallHierarchy() async throws {
    let ws = try await IndexedSingleSwiftFileWorkspace(
      """
      func 1️⃣a() {}

      func 2️⃣b(x: String) {
        3️⃣a()
        4️⃣c()
        5️⃣b(x: "test")
      }

      func 6️⃣c() {
        7️⃣a()
        if 8️⃣d() {
          9️⃣c()
        }
      }

      func 🔟d() -> Bool {
        false
      }

      a()
      b(x: "test")
      """
    )

    func callHierarchy(at position: Position) async throws -> [CallHierarchyItem] {
      let request = CallHierarchyPrepareRequest(textDocument: TextDocumentIdentifier(ws.fileURI), position: position)
      return try await ws.testClient.send(request) ?? []
    }

    func incomingCalls(at position: Position) async throws -> [CallHierarchyIncomingCall] {
      guard let item = try await callHierarchy(at: position).first else {
        XCTFail("call hierarchy at \(position) was empty")
        return []
      }
      let request = CallHierarchyIncomingCallsRequest(item: item)
      return try await ws.testClient.send(request) ?? []
    }

    func outgoingCalls(at position: Position) async throws -> [CallHierarchyOutgoingCall] {
      guard let item = try await callHierarchy(at: position).first else {
        XCTFail("call hierarchy at \(position) was empty")
        return []
      }
      let request = CallHierarchyOutgoingCallsRequest(item: item)
      return try await ws.testClient.send(request) ?? []
    }

    func usr(at position: Position) async throws -> String {
      guard let item = try await callHierarchy(at: position).first else {
        XCTFail("call hierarchy at \(position) was empty")
        return ""
      }
      guard case let .dictionary(data) = item.data,
        case let .string(usr) = data["usr"]
      else {
        XCTFail("unable to find usr in call hierarchy in item data dictionary")
        return ""
      }
      return usr
    }

    // Convenience functions

    func item(
      _ name: String,
      _ kind: SymbolKind,
      detail: String = "test",
      usr: String,
      at position: Position
    ) -> CallHierarchyItem {
      return CallHierarchyItem(
        name: name,
        kind: kind,
        tags: nil,
        detail: detail,
        uri: ws.fileURI,
        range: Range(position),
        selectionRange: Range(position),
        data: .dictionary([
          "usr": .string(usr),
          "uri": .string(ws.fileURI.stringValue),
        ])
      )
    }

    let aUsr = try await usr(at: ws.positions["1️⃣"])
    let bUsr = try await usr(at: ws.positions["2️⃣"])
    let cUsr = try await usr(at: ws.positions["6️⃣"])
    let dUsr = try await usr(at: ws.positions["🔟"])

    // Test outgoing call hierarchy

    assertEqual(try await outgoingCalls(at: ws.positions["1️⃣"]), [])
    assertEqual(
      try await outgoingCalls(at: ws.positions["2️⃣"]),
      [
        CallHierarchyOutgoingCall(
          to: item("a()", .function, usr: aUsr, at: ws.positions["1️⃣"]),
          fromRanges: [Range(ws.positions["3️⃣"])]
        ),
        CallHierarchyOutgoingCall(
          to: item("c()", .function, usr: cUsr, at: ws.positions["6️⃣"]),
          fromRanges: [Range(ws.positions["4️⃣"])]
        ),
        CallHierarchyOutgoingCall(
          to: item("b(x:)", .function, usr: bUsr, at: ws.positions["2️⃣"]),
          fromRanges: [Range(ws.positions["5️⃣"])]
        ),
      ]
    )
    assertEqual(
      try await outgoingCalls(at: ws.positions["6️⃣"]),
      [
        CallHierarchyOutgoingCall(
          to: item("a()", .function, usr: aUsr, at: ws.positions["1️⃣"]),
          fromRanges: [Range(ws.positions["7️⃣"])]
        ),
        CallHierarchyOutgoingCall(
          to: item("d()", .function, usr: dUsr, at: ws.positions["🔟"]),
          fromRanges: [Range(ws.positions["8️⃣"])]
        ),
        CallHierarchyOutgoingCall(
          to: item("c()", .function, usr: cUsr, at: ws.positions["6️⃣"]),
          fromRanges: [Range(ws.positions["9️⃣"])]
        ),
      ]
    )

    // Test incoming call hierarchy

    assertEqual(
      try await incomingCalls(at: ws.positions["1️⃣"]),
      [
        CallHierarchyIncomingCall(
          from: item("b(x:)", .function, usr: bUsr, at: ws.positions["2️⃣"]),
          fromRanges: [Range(ws.positions["3️⃣"])]
        ),
        CallHierarchyIncomingCall(
          from: item("c()", .function, usr: cUsr, at: ws.positions["6️⃣"]),
          fromRanges: [Range(ws.positions["7️⃣"])]
        ),
      ]
    )
    assertEqual(
      try await incomingCalls(at: ws.positions["2️⃣"]),
      [
        CallHierarchyIncomingCall(
          from: item("b(x:)", .function, usr: bUsr, at: ws.positions["2️⃣"]),
          fromRanges: [Range(ws.positions["5️⃣"])]
        )
      ]
    )
    assertEqual(
      try await incomingCalls(at: ws.positions["🔟"]),
      [
        CallHierarchyIncomingCall(
          from: item("c()", .function, usr: cUsr, at: ws.positions["6️⃣"]),
          fromRanges: [Range(ws.positions["8️⃣"])]
        )
      ]
    )
  }
}
