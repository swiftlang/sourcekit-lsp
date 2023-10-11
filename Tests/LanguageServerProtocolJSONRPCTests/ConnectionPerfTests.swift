//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LSPTestSupport
import LanguageServerProtocolJSONRPC
import XCTest

class ConnectionPerfTests: PerfTestCase {

  var connection: TestJSONRPCConnection! = nil

  override func setUp() {
    connection = TestJSONRPCConnection()
  }

  override func tearDown() {
    connection.close()
  }

  func testEcho1() {
    let client = connection.client
    self.measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
      let expectation = self.expectation(description: "response received")
      self.startMeasuring()
      _ = client.send(EchoRequest(string: "hello!")) { _ in
        self.stopMeasuring()
        expectation.fulfill()
      }

      waitForExpectations(timeout: defaultTimeout)
    }
  }

  func testEcho100Latency() {
    let client = connection.client
    let sema = DispatchSemaphore(value: 0)
    self.measure {
      for _ in 1...100 {
        _ = client.send(EchoRequest(string: "hello!")) { _ in
          sema.signal()
        }
        XCTAssertEqual(sema.wait(timeout: .now() + .seconds(Int(defaultTimeout))), .success)
      }
    }
  }

  func testEcho100Throughput() {
    let client = connection.client
    let sema = DispatchSemaphore(value: 0)
    self.measure {
      DispatchQueue.concurrentPerform(
        iterations: 100,
        execute: { _ in
          _ = client.send(EchoRequest(string: "hello!")) { _ in
            sema.signal()
          }
        }
      )
      for _ in 1...100 {
        XCTAssertEqual(sema.wait(timeout: .now() + .seconds(Int(defaultTimeout))), .success)
      }
    }
  }
}
