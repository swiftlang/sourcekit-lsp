//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SKTestSupport
import SemanticIndex
import XCTest

final class ModuleVariantTrackerTests: SourceKitLSPTestCase {
  func testReportCountsDistinctVariantsAcrossModuleMaps() async throws {
    try await withTestScratchDir { scratchDir in
      let swift5Map = scratchDir.appendingPathComponent("A-dependencies.json")
      let swift6Map = scratchDir.appendingPathComponent("B-dependencies.json")
      try """
      [
        {"moduleName": "Foundation", "modulePath": "/prebuilt/Foundation.swiftmodule", "isFramework": true},
        {"moduleName": "Shims", "clangModulePath": "/pcms/Shims-5.pcm", "clangModuleMapPath": "/shims/module.modulemap"}
      ]
      """.write(to: swift5Map, atomically: true, encoding: .utf8)
      try """
      [
        {"moduleName": "Foundation", "modulePath": "/prebuilt/Foundation.swiftmodule", "isFramework": true},
        {"moduleName": "Shims", "clangModulePath": "/pcms/Shims-6.pcm", "clangModuleMapPath": "/shims/module.modulemap"}
      ]
      """.write(to: swift6Map, atomically: true, encoding: .utf8)

      let tracker = ModuleVariantTracker()
      tracker.recordIndexInvocation([
        "swiftc", "-Xfrontend", "-explicit-swift-module-map-file", "-Xfrontend", swift5Map.path, "a.swift",
      ])
      tracker.recordIndexInvocation(["swiftc", "-explicit-swift-module-map-file", swift6Map.path, "b.swift"])
      // An invocation that reuses a module map does not count its modules again.
      tracker.recordIndexInvocation(["swiftc", "-explicit-swift-module-map-file", swift6Map.path, "c.swift"])
      // An invocation without an explicit module map contributes nothing.
      tracker.recordIndexInvocation(["swiftc", "d.swift"])

      XCTAssertEqual(
        tracker.takeReport(),
        """
        2 modules, 3 variants, from 2 explicit module maps

        Modules with more than one variant:
          Shims (Clang): 2
            /pcms/Shims-5.pcm
            /pcms/Shims-6.pcm

        All modules:
          Shims (Clang): 2
          Foundation (Swift): 1

        """
      )
      XCTAssertNil(tracker.takeReport())
    }
  }
}
