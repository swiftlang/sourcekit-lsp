//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SKLogging
package import Testing
public import XCTest

/// Base class for a unit tests in SourceKit-LSP.
/// Handles configuring the logging system before running tests.
open class SourceKitLSPTestCase: XCTestCase {
  override public static func setUp() {
    LoggingScope.configureDefaultLoggingSubsystem("org.swift.sourcekit-lsp.tests")
  }
}

package struct ConfigureLoggingTrait: TestTrait, SuiteTrait, TestScoping {
  package func provideScope(
    for test: Test,
    testCase: Test.Case?,
    performing function: @concurrent @Sendable () async throws -> Void
  ) async throws {
    LoggingScope.configureDefaultLoggingSubsystem("org.swift.sourcekit-lsp.tests")
    try await function()
  }
}

extension Trait where Self == ConfigureLoggingTrait {
  package static var configureLogging: Self {
    Self()
  }
}
