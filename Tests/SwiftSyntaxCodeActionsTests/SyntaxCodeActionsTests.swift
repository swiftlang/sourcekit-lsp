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

import SwiftSyntaxCodeActions
import XCTest

final class SyntaxCodeActionsTests: XCTestCase {
  func testNoDuplicateCodeActionProviders() {
    var seen: Set<ObjectIdentifier> = []
    for provider in allSyntaxCodeActionProviders {
      let identifier = ObjectIdentifier(provider)
      XCTAssertFalse(
        seen.contains(identifier),
        "Duplicate code action provider in allSyntaxCodeActionProviders: \(provider)"
      )
      seen.insert(identifier)
    }
  }

  func testCodeActionProvidersAreSorted() {
    let names =
      allSyntaxCodeActionProviders
      .filter { "\($0)" != "PackageManifestEdits" }
      .map { "\($0)" }
    XCTAssertEqual(
      names,
      names.sorted(),
      "allSyntaxCodeActionProviders should be alphabetically sorted"
    )
  }
}
