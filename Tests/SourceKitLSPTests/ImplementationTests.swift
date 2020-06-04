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
import LanguageServerProtocol
import XCTest

final class ImplementationTests: XCTestCase {
  func testImplementation() throws {
    let ws = try staticSourceKitTibsWorkspace(name: "Implementation")!
    try ws.buildAndIndex()

    try ws.openDocument(ws.testLoc("a.swift").url, language: .swift)
    try ws.openDocument(ws.testLoc("b.swift").url, language: .swift)

    func impls(at testLoc: TestLocation) throws -> Set<Location> {
      let textDocument = testLoc.docIdentifier
      let request = ImplementationRequest(textDocument: textDocument, position: Position(testLoc))
      let response = try ws.sk.sendSync(request)
      guard case .locations(let implementations) = response else {
        XCTFail("Response was not locations")
        return []
      }
      return Set(implementations)
    }
    func testLoc(_ name: String) -> TestLocation {
      ws.testLoc(name)
    }  
    func loc(_ name: String) -> Location {
      Location(badUTF16: ws.testLoc(name))
    }
    
    try XCTAssertEqual(impls(at: testLoc("Protocol")), [loc("StructConformance")])
    try XCTAssertEqual(impls(at: testLoc("ProtocolStaticVar")), [loc("StructStaticVar")])
    try XCTAssertEqual(impls(at: testLoc("ProtocolStaticFunction")), [loc("StructStaticFunction")])
    try XCTAssertEqual(impls(at: testLoc("ProtocolVariable")), [loc("StructVariable")])
    try XCTAssertEqual(impls(at: testLoc("ProtocolFunction")), [loc("StructFunction")])
    try XCTAssertEqual(impls(at: testLoc("Class")), [loc("SubclassConformance")])
    try XCTAssertEqual(impls(at: testLoc("ClassClassVar")), [loc("SubclassClassVar")])
    try XCTAssertEqual(impls(at: testLoc("ClassClassFunction")), [loc("SubclassClassFunction")])
    try XCTAssertEqual(impls(at: testLoc("ClassVariable")), [loc("SubclassVariable")])
    try XCTAssertEqual(impls(at: testLoc("ClassFunction")), [loc("SubclassFunction")])

    try XCTAssertEqual(impls(at: testLoc("Sepulcidae")), [loc("ParapamphiliinaeConformance"), loc("XyelulinaeConformance"), loc("TrematothoracinaeConformance")])
    try XCTAssertEqual(impls(at: testLoc("Parapamphiliinae")), [loc("MicramphiliusConformance"), loc("PamparaphiliusConformance")])
    try XCTAssertEqual(impls(at: testLoc("Xyelulinae")), [loc("XyelulaConformance")])
    try XCTAssertEqual(impls(at: testLoc("Trematothoracinae")), [])

    try XCTAssertEqual(impls(at: testLoc("Prozaiczne")), [loc("MurkwiaConformance2"), loc("SepulkaConformance1")])
    try XCTAssertEqual(impls(at: testLoc("Sepulkowate")), [loc("MurkwiaConformance1"), loc("SepulkaConformance2"), loc("PćmaŁagodnaConformance"), loc("PćmaZwyczajnaConformance")])
    // FIXME: sourcekit returns wrong locations for the function (subclasses that don't override it, and extensions that don't implement it)
    // try XCTAssertEqual(impls(at: testLoc("rozpocznijSepulenie")), [loc("MurkwiaFunc"), loc("SepulkaFunc"), loc("PćmaŁagodnaFunc"), loc("PćmaZwyczajnaFunc")])
    try XCTAssertEqual(impls(at: testLoc("Murkwia")), [])
    try XCTAssertEqual(impls(at: testLoc("MurkwiaFunc")), [])
    try XCTAssertEqual(impls(at: testLoc("Sepulka")), [loc("SepulkaDwuusznaConformance"), loc("SepulkaPrzechylnaConformance")])
    try XCTAssertEqual(impls(at: testLoc("SepulkaVar")), [loc("SepulkaDwuusznaVar"), loc("SepulkaPrzechylnaVar")])
    try XCTAssertEqual(impls(at: testLoc("SepulkaFunc")), [])
  }
}
