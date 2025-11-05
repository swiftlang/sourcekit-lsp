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

package import BuildServerIntegration
import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
package import SemanticIndex

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

/// Closures can be used to inspect or modify internal behavior in SourceKit-LSP.
public struct Hooks: Sendable {
  package var indexHooks: IndexHooks

  package var buildServerHooks: BuildServerHooks

  /// A hook that will be executed before a request is handled.
  ///
  /// This allows requests to be artificially delayed.
  package var preHandleRequest: (@Sendable (any RequestType) async -> Void)?

  /// Closure that is executed before a request is forwarded to clangd.
  ///
  /// This allows tests to simulate a `clangd` process that's unresponsive.
  package var preForwardRequestToClangd: (@Sendable (any RequestType) async -> Void)?

  public init() {
    self.init(indexHooks: IndexHooks(), buildServerHooks: BuildServerHooks())
  }

  package init(
    indexHooks: IndexHooks = IndexHooks(),
    buildServerHooks: BuildServerHooks = BuildServerHooks(),
    preHandleRequest: (@Sendable (any RequestType) async -> Void)? = nil,
    preForwardRequestToClangd: (@Sendable (any RequestType) async -> Void)? = nil
  ) {
    self.indexHooks = indexHooks
    self.buildServerHooks = buildServerHooks
    self.preHandleRequest = preHandleRequest
    self.preForwardRequestToClangd = preForwardRequestToClangd
  }
}
