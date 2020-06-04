//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SourceKitLSP
import SKCore
import SKTestSupport
import LanguageServerProtocol
import IndexStoreDB
import XCTest

final class MainFilesProviderTests: XCTestCase {

  func testMainFilesChanged() {
    let ws = try! mutableSourceKitTibsTestWorkspace(name: "MainFiles")!
    let indexDelegate = SourceKitIndexDelegate()
    ws.tibsWorkspace.delegate = indexDelegate

    final class TestMainFilesDelegate: MainFilesDelegate {
      var expectation: XCTestExpectation
      init(_ expectation: XCTestExpectation) { self.expectation = expectation }
      func mainFilesChanged() {
        expectation.fulfill()
      }
    }

    let mainFilesDelegate = TestMainFilesDelegate(expectation(description: "main files changed"))
    indexDelegate.registerMainFileChanged(mainFilesDelegate)

    let a = ws.testLoc("a_func").docIdentifier.uri
    let b = ws.testLoc("b_func").docIdentifier.uri
    let c = ws.testLoc("c_func").docIdentifier.uri
    let d = ws.testLoc("d_func").docIdentifier.uri
    let unique_h = ws.testLoc("unique").docIdentifier.uri
    let shared_h = ws.testLoc("shared").docIdentifier.uri
    let bridging = ws.testLoc("bridging").docIdentifier.uri

    XCTAssertEqual(ws.index.mainFilesContainingFile(a), [])
    XCTAssertEqual(ws.index.mainFilesContainingFile(b), [])
    XCTAssertEqual(ws.index.mainFilesContainingFile(c), [])
    XCTAssertEqual(ws.index.mainFilesContainingFile(d), [])
    XCTAssertEqual(ws.index.mainFilesContainingFile(unique_h), [])
    XCTAssertEqual(ws.index.mainFilesContainingFile(shared_h), [])
    XCTAssertEqual(ws.index.mainFilesContainingFile(bridging), [])

    try! ws.buildAndIndex()

    XCTAssertEqual(ws.index.mainFilesContainingFile(a), [a])
    XCTAssertEqual(ws.index.mainFilesContainingFile(b), [b])
    XCTAssertEqual(ws.index.mainFilesContainingFile(c), [c])
    XCTAssertEqual(ws.index.mainFilesContainingFile(d), [d])
    XCTAssertEqual(ws.index.mainFilesContainingFile(unique_h), [d])
    XCTAssertEqual(ws.index.mainFilesContainingFile(shared_h), [c, d])
    XCTAssertEqual(ws.index.mainFilesContainingFile(bridging), [c])

    wait(for: [mainFilesDelegate.expectation], timeout: 15)

    try! ws.edit { changes, _ in
      changes.write("""
        #include "bridging.h"
        void d_new(void) { bridging(); }
        """, to: d.fileURL!)

      changes.write("""
      #include "unique.h"
      void c_new(void) { unique(); }
      """, to: c.fileURL!)
    }

    mainFilesDelegate.expectation = expectation(description: "main files changed after edit")
    try! ws.buildAndIndex()

    XCTAssertEqual(ws.index.mainFilesContainingFile(unique_h), [c])
    XCTAssertEqual(ws.index.mainFilesContainingFile(shared_h), [])
    XCTAssertEqual(ws.index.mainFilesContainingFile(bridging), [d])

    wait(for: [mainFilesDelegate.expectation], timeout: 15)

    XCTAssertEqual(ws.index.mainFilesContainingFile(DocumentURI(string: "not:file")), [])
  }
}
