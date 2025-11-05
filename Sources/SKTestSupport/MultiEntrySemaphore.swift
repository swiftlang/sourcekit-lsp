//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

/// A semaphore that, once signaled, will pass on every `wait` call. Ie. the semaphore only needs to be signaled once
/// and from that point onwards it can be acquired as many times as necessary.
///
/// Use cases of this are for example to delay indexing until a some other task has been performed. But once that is
/// done, all index operations should be able to run, not just one.
package final class MultiEntrySemaphore: Sendable {
  private let name: String
  private let signaled = AtomicBool(initialValue: false)

  package init(name: String) {
    self.name = name
  }

  package func signal() {
    signaled.value = true
  }

  package func waitOrThrow() async throws {
    do {
      try await repeatUntilExpectedResult(sleepInterval: .seconds(0.01)) { signaled.value }
    } catch {
      struct TimeoutError: Error, CustomStringConvertible {
        let name: String
        var description: String { "\(name) timed out" }
      }
      throw TimeoutError(name: "\(name) timed out")
    }
  }

  package func waitOrXCTFail(file: StaticString = #filePath, line: UInt = #line) async {
    do {
      try await waitOrThrow()
    } catch {
      XCTFail("\(error)", file: file, line: line)
    }
  }
}
