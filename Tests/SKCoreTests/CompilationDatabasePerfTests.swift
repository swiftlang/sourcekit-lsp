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

import LanguageServerProtocol
import LSPTestSupport
import SKCore
import TSCBasic
import XCTest

final class CompilationDatabasePerfTests: PerfTestCase {
  func testSplitShellEscapedCommand() {
    var input = "asdf"
    for i in 0..<10000 {
      if i % 10 == 9 {
        input += " \"foo\(i) \""
      } else if i % 10 == 6 {
        input += " fo\'o\(i) \'"
      } else if i % 3 == 0{
        input += " foo\(i)-------a-long--string-of---------stuff"
      } else {
        input += " foo\(i)"
      }
    }

    XCTAssertEqual(splitShellEscapedCommand(input).count, 10001)

    self.measure {
      _ = splitShellEscapedCommand(input)
    }
  }
}
