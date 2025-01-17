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
package import Foundation
#else
import LanguageServerProtocol
import Foundation
#endif

package struct SwiftPMTestHooks: Sendable {
  package var reloadPackageDidStart: (@Sendable () async -> Void)?
  package var reloadPackageDidFinish: (@Sendable () async -> Void)?

  package init(
    reloadPackageDidStart: (@Sendable () async -> Void)? = nil,
    reloadPackageDidFinish: (@Sendable () async -> Void)? = nil
  ) {
    self.reloadPackageDidStart = reloadPackageDidStart
    self.reloadPackageDidFinish = reloadPackageDidFinish
  }
}

/// When running SourceKit-LSP in-process, allows the creator of `SourceKitLSPServer` to create the build system instead
/// of SourceKit-LSP creating build systems as needed.
package protocol BuildSystemInjector: Sendable {
  func createBuildSystem(projectRoot: URL, connectionToSourceKitLSP: any Connection) async -> BuiltInBuildSystem
}

package struct BuildSystemHooks: Sendable {
  package var swiftPMTestHooks: SwiftPMTestHooks

  /// A hook that will be executed before a request is handled by a `BuiltInBuildSystem`.
  ///
  /// This allows requests to be artificially delayed.
  package var preHandleRequest: (@Sendable (any RequestType) async -> Void)?

  package var buildSystemInjector: BuildSystemInjector?

  package init(
    swiftPMTestHooks: SwiftPMTestHooks = SwiftPMTestHooks(),
    preHandleRequest: (@Sendable (any RequestType) async -> Void)? = nil,
    buildSystemInjector: BuildSystemInjector? = nil
  ) {
    self.swiftPMTestHooks = swiftPMTestHooks
    self.preHandleRequest = preHandleRequest
    self.buildSystemInjector = buildSystemInjector
  }
}
