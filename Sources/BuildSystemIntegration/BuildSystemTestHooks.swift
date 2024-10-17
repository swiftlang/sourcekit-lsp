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

#if compiler(>=6)
package import LanguageServerProtocol
#else
import LanguageServerProtocol
#endif

package struct BuildSystemTestHooks: Sendable {
  package var swiftPMTestHooks: SwiftPMTestHooks

  /// A hook that will be executed before a request is handled by a `BuiltInBuildSystem`.
  ///
  /// This allows requests to be artificially delayed.
  package var handleRequest: (@Sendable (any RequestType) async -> Void)?

  package init(
    swiftPMTestHooks: SwiftPMTestHooks = SwiftPMTestHooks(),
    handleRequest: (@Sendable (any RequestType) async -> Void)? = nil
  ) {
    self.swiftPMTestHooks = swiftPMTestHooks
    self.handleRequest = handleRequest
  }
}
