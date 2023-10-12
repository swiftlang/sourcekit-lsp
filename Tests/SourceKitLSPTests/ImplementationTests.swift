//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ISDBTestSupport
import LSPTestSupport
import LanguageServerProtocol
import TSCBasic
import XCTest

final class ImplementationTests: XCTestCase {
  func testImplementation() async throws {
    let ws = try await staticSourceKitTibsWorkspace(name: "Implementation")!
    try ws.buildAndIndex()

    try ws.openDocument(ws.testLoc("a.swift").url, language: .swift)
    try ws.openDocument(ws.testLoc("b.swift").url, language: .swift)

    func impls(at testLoc: TestLocation) async throws -> Set<Location> {
      let textDocument = testLoc.docIdentifier
      let request = ImplementationRequest(textDocument: textDocument, position: Position(testLoc))
      let response = try await ws.testServer.send(request)
      guard case .locations(let implementations) = response else {
        XCTFail("Response was not locations")
        return []
      }
      return Set(implementations)
    }
    func testLoc(_ name: String) -> TestLocation {
      ws.testLoc(name)
    }
    func loc(_ name: String) throws -> Location {
      let location: TestLocation = ws.testLoc(name)
      return Location(
        badUTF16: TestLocation(
          url: try location.docUri.nativeURI.fileURL!,
          line: location.line,
          utf8Column: location.utf8Column,
          utf16Column: location.utf16Column
        )
      )
    }

    try assertEqual(await impls(at: testLoc("Protocol")), [loc("StructConformance")])
    try assertEqual(await impls(at: testLoc("ProtocolStaticVar")), [loc("StructStaticVar")])
    try assertEqual(await impls(at: testLoc("ProtocolStaticFunction")), [loc("StructStaticFunction")])
    try assertEqual(await impls(at: testLoc("ProtocolVariable")), [loc("StructVariable")])
    try assertEqual(await impls(at: testLoc("ProtocolFunction")), [loc("StructFunction")])
    try assertEqual(await impls(at: testLoc("Class")), [loc("SubclassConformance")])
    try assertEqual(await impls(at: testLoc("ClassClassVar")), [loc("SubclassClassVar")])
    try assertEqual(await impls(at: testLoc("ClassClassFunction")), [loc("SubclassClassFunction")])
    try assertEqual(await impls(at: testLoc("ClassVariable")), [loc("SubclassVariable")])
    try assertEqual(await impls(at: testLoc("ClassFunction")), [loc("SubclassFunction")])

    try assertEqual(
      await impls(at: testLoc("Sepulcidae")),
      [loc("ParapamphiliinaeConformance"), loc("XyelulinaeConformance"), loc("TrematothoracinaeConformance")]
    )
    try assertEqual(
      await impls(at: testLoc("Parapamphiliinae")),
      [loc("MicramphiliusConformance"), loc("PamparaphiliusConformance")]
    )
    try assertEqual(await impls(at: testLoc("Xyelulinae")), [loc("XyelulaConformance")])
    try assertEqual(await impls(at: testLoc("Trematothoracinae")), [])

    try assertEqual(await impls(at: testLoc("Prozaiczne")), [loc("MurkwiaConformance2"), loc("SepulkaConformance1")])
    try assertEqual(
      await impls(at: testLoc("Sepulkowate")),
      [
        loc("MurkwiaConformance1"), loc("SepulkaConformance2"), loc("PćmaŁagodnaConformance"),
        loc("PćmaZwyczajnaConformance"),
      ]
    )
    // FIXME: sourcekit returns wrong locations for the function (subclasses that don't override it, and extensions that don't implement it)
    // try XCTAssertEqual(impls(at: testLoc("rozpocznijSepulenie")), [loc("MurkwiaFunc"), loc("SepulkaFunc"), loc("PćmaŁagodnaFunc"), loc("PćmaZwyczajnaFunc")])
    try assertEqual(await impls(at: testLoc("Murkwia")), [])
    try assertEqual(await impls(at: testLoc("MurkwiaFunc")), [])
    try assertEqual(
      await impls(at: testLoc("Sepulka")),
      [loc("SepulkaDwuusznaConformance"), loc("SepulkaPrzechylnaConformance")]
    )
    try assertEqual(await impls(at: testLoc("SepulkaVar")), [loc("SepulkaDwuusznaVar"), loc("SepulkaPrzechylnaVar")])
    try assertEqual(await impls(at: testLoc("SepulkaFunc")), [])
  }
}
