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

import XCTest

/// Base class for a performance test case in SourceKit-LSP.
///
/// This allows writing performance tests whose performance tracking is only
/// enabled when ENABLE_PERF_TESTS is defined. Otherwise, the test is still
/// executed, but no metrics are enabled, and the measured block is only run
/// once, which is useful to avoid failures due to high variability in
/// continuous integration.
open class PerfTestCase: XCTestCase {

#if !ENABLE_PERF_TESTS

  #if os(macOS)
    open override func startMeasuring() {}
    open override func stopMeasuring() {}
    open override func measureMetrics(
      _: [XCTPerformanceMetric],
      automaticallyStartMeasuring: Bool,
      for block: () -> Void)
    {
      block()
    }
  #else
    // In corelibs-xctest, these methods are public, not open, so we can only
    // shadow them.
    public func startMeasuring() {}
    public func stopMeasuring() {}
    public func measureMetrics(
      _: [XCTPerformanceMetric],
      automaticallyStartMeasuring: Bool,
      for block: () -> Void)
    {
      block()
    }
    public func measure(block: () -> Void) {
      block()
    }
  #endif
#endif

}
