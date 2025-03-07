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

package import BuildSystemIntegration
import Foundation
package import LanguageServerProtocol
import LanguageServerProtocolExtensions
package import SemanticIndex

import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath

/// Closures can be used to inspect or modify internal behavior in SourceKit-LSP.
public struct Hooks: Sendable {
  package var indexHooks: IndexHooks

  package var buildSystemHooks: BuildSystemHooks

  /// A hook that will be executed before a request is handled.
  ///
  /// This allows requests to be artificially delayed.
  package var preHandleRequest: (@Sendable (any RequestType) async -> Void)?

  public init() {
    self.init(indexHooks: IndexHooks(), buildSystemHooks: BuildSystemHooks())
  }

  package init(
    indexHooks: IndexHooks = IndexHooks(),
    buildSystemHooks: BuildSystemHooks = BuildSystemHooks(),
    preHandleRequest: (@Sendable (any RequestType) async -> Void)? = nil
  ) {
    self.indexHooks = indexHooks
    self.buildSystemHooks = buildSystemHooks
    self.preHandleRequest = preHandleRequest
  }
}
