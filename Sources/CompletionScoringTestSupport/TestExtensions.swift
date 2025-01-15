//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftExtensions
import XCTest

#if compiler(>=6)
package import CompletionScoring
#else
import CompletionScoring
#endif

@inline(never)
package func drain<T>(_ value: T) {}

func duration(of body: () -> ()) -> TimeInterval {
  let start = ProcessInfo.processInfo.systemUptime
  body()
  return ProcessInfo.processInfo.systemUptime - start
}

extension RandomNumberGenerator {
  mutating func nextBool() -> Bool {
    (next() & 0x01 == 0x01)
  }
}

package func withEachPermutation<T>(_ a: T, _ b: T, body: (T, T) -> ()) {
  body(a, b)
  body(b, a)
}

extension XCTestCase {
  private func heatUp() {
    var integers = 1024
    var elapsed = 0.0
    while elapsed < 1.0 {
      elapsed += duration {
        let integers = Array(count: integers) {
          UInt64.random(in: 0...UInt64.max)
        }
        DispatchQueue.concurrentPerform(iterations: 128) { _ in
          integers.withUnsafeBytes { bytes in
            var hasher = Hasher()
            hasher.combine(bytes: bytes)
            drain(hasher.finalize())
          }
        }
      }
      integers *= 2
    }
  }

  private func coolDown() {
    Thread.sleep(forTimeInterval: 2.0)
  }

  #if canImport(Darwin)
  func induceThermalRange(_ range: ClosedRange<Int>) {
    var temperature: Int
    repeat {
      temperature = ProcessInfo.processInfo.thermalLevel()
      if temperature < range.lowerBound {
        print("Too Cold: \(temperature)")
        heatUp()
      } else if temperature > range.upperBound {
        print("Too Hot: \(temperature)")
        coolDown()
      }
    } while !range.contains(temperature)
  }

  private static let targetThermalRange: ClosedRange<Int>? = {
    if ProcessInfo.processInfo.environment["SOURCEKIT_LSP_PERFORMANCE_MEASUREMENTS_ENABLE_THERMAL_THROTTLING"]
      != nil
    {
      // This range is arbitrary. All that matters is that the same values are used on the baseline and the branch.
      let target =
        ProcessInfo.processInfo.environment["SOURCEKIT_LSP_PERFORMANCE_MEASUREMENTS_THERMAL_TARGET"].flatMap(
          Int.init
        )
        ?? 75
      let variance =
        ProcessInfo.processInfo.environment["SOURCEKIT_LSP_PERFORMANCE_MEASUREMENTS_THERMAL_VARIANCE"].flatMap(
          Int.init
        )
        ?? 5
      return (target - variance)...(target + variance)
    } else {
      return nil
    }
  }()
  #endif

  private static let measurementsLogFile: String? = {
    UserDefaults.standard.string(forKey: "TestMeasurementLogPath")
  }()

  static let printBeginingOfLog = AtomicBool(initialValue: true)

  private static func openPerformanceLog() throws -> FileHandle? {
    try measurementsLogFile.map { path in
      if !FileManager.default.fileExists(atPath: path) {
        try FileManager.default.createDirectory(
          at: URL(fileURLWithPath: path).deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: path, contents: Data())
      }
      let logFD = try FileHandle(forWritingAtPath: path).unwrap(orThrow: "Opening \(path) failed")
      try logFD.seekToEnd()
      if printBeginingOfLog.value {
        try logFD.print("========= \(Date().description(with: .current)) =========")
        printBeginingOfLog.value = false
      }
      return logFD
    }
  }

  func tryOrFailTest<R>(_ expression: @autoclosure () throws -> R?, message: String) -> R? {
    do {
      return try expression()
    } catch {
      XCTFail("\(message): \(error)")
      return nil
    }
  }

  /// Run `body()` `iterations`, gathering timing stats, and print them.
  /// In between runs, coax for the machine into an arbitrary but consistent thermal state by either sleeping or doing
  /// pointless work so that results are more comparable run to run, no matter else is happening on the machine.
  package func gaugeTiming(iterations: Int = 1, testName: String = #function, _ body: () -> ()) {
    let logFD = tryOrFailTest(try Self.openPerformanceLog(), message: "Failed to open performance log")
    var timings = Timings()
    for iteration in 0..<iterations {
      #if canImport(Darwin)
      if let targetThermalRange = Self.targetThermalRange {
        induceThermalRange(targetThermalRange)
      }
      let thermalLevel = ProcessInfo.processInfo.thermalLevel()
      #else
      let thermalLevel = "unknown"
      #endif
      let duration = duration(of: body)
      let stats = timings.append(duration)
      let confidence = timings.confidenceOfMean_95Percent
      let confidencePercentOfAverage = confidence / stats.average * 100
      let consoleMessage =
        """
        [\(iteration.format("%4ld"))]: \
        current: \(duration.format("%0.4f")), \
        min: \(stats.min.format("%0.4f")), \
        max: \(stats.max.format("%0.4f")), \
        avg: \(stats.average.format("%0.4f")), \
        confidence:±\(confidencePercentOfAverage.format("%0.2f"))% \
        thermal: \(thermalLevel)
        """
      let logMessage = "\(testName.prefix(while: \.isLetter)),\(duration.format("%0.4f")),\(thermalLevel)"
      print(consoleMessage)
      tryOrFailTest(try logFD?.print(logMessage), message: "Failed to write to log")
    }
  }
}

#if canImport(Darwin)
extension ProcessInfo {
  func thermalLevel() -> Int {
    var thermalLevel: UInt64 = 0
    var size: size_t = MemoryLayout<UInt64>.size
    sysctlbyname("machdep.xcpm.cpu_thermal_level", &thermalLevel, &size, nil, 0)
    return Int(thermalLevel)
  }
}
#endif

extension String {
  fileprivate func dropSuffix(_ suffix: String) -> String {
    if hasSuffix(suffix) {
      return String(dropLast(suffix.count))
    }
    return self
  }

  fileprivate func dropPrefix(_ prefix: String) -> String {
    if hasPrefix(prefix) {
      return String(dropFirst(prefix.count))
    }
    return self
  }

  package func allocateCopyOfUTF8Buffer() -> CompletionScoring.Pattern.UTF8Bytes {
    withUncachedUTF8Bytes { utf8Buffer in
      UnsafeBufferPointer.allocate(copyOf: utf8Buffer)
    }
  }
}

extension FileHandle {
  func write(_ text: String) throws {
    try text.withUncachedUTF8Bytes { bytes in
      try write(contentsOf: bytes)
    }
  }

  func print(_ text: String) throws {
    try write(text)
    try write("\n")
  }
}

extension Double {
  func format(_ specifier: StringLiteralType) -> String {
    String(format: specifier, self)
  }
}

extension Int {
  func format(_ specifier: StringLiteralType) -> String {
    String(format: specifier, self)
  }
}

extension CandidateBatch {
  package init(symbols: [String]) {
    self.init(candidates: symbols, contentType: .codeCompletionSymbol)
  }
}
