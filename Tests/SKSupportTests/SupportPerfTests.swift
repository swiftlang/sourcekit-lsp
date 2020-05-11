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
import SKSupport
import SKTestSupport
import XCTest

final class SupportPerfTests: PerfTestCase {

  func testLineTableAppendPerf() {

    let characters: [Character] = [
      "\t", "\n"
    ] + (32...126).map { Character(UnicodeScalar($0)) }

    #if DEBUG || !ENABLE_PERF_TESTS
    let iterations = 1_000
    #else
    let iterations = 10_000
    #endif

    self.measure {
      var lcg = SimpleLCG(seed: 1)
      var t = LineTable("")
      var line = 0
      var col = 0
      for _ in 1...iterations {
        let c = characters.randomElement(using: &lcg)!
        t.replace(fromLine: line, utf16Offset: col, toLine: line, utf16Offset: col, with: String(c))
        col += 1
        if c == "\n" {
          line += 1
          col = 0
        }
      }
    }
  }

  func testLineTableSingleCharEditPerf() {
    let characters: [Character] = [
      "\t", "\n"
      ] + (32...126).map { Character(UnicodeScalar($0)) }

    #if DEBUG || !ENABLE_PERF_TESTS
    let iterations = 1_000
    let size = 1_000
    #else
    let iterations = 10_000
    let size = 10_000
    #endif

    self.measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
      var lcg = SimpleLCG(seed: 1)
      var str = ""
      for _ in 1...size {
        str += String(characters.randomElement(using: &lcg)!)
      }

      var t = LineTable(str)

      self.startMeasuring()

      for _ in 1...iterations {
        let line = (0 ..< (t.count-1)).randomElement(using: &lcg) ?? 0
        let col = (0 ..< t[line].utf16.count).randomElement(using: &lcg) ?? 0
        let len = t[line].isEmpty ? 0 : Bool.random() ? 1 : 0
        var newText = String(characters.randomElement(using: &lcg)!)
        if len == 1 && Bool.random(using: &lcg) {
          newText = "" // deletion
        }

        t.replace(fromLine: line, utf16Offset: col, utf16Length: len, with: newText)
      }

      self.stopMeasuring()
    }
  }
}
