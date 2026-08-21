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

@_spi(SourceKitLSP) package import BuildServerProtocol
package import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol

package struct BuildServerHooks: Sendable {
  /// A hook that will be executed before a request is handled by a `BuiltInBuildServer`.
  ///
  /// This allows requests to be artificially delayed.
  package var preHandleRequest: (@Sendable (any RequestType) async -> Void)?

  /// A hook that will be executed before a notification received from the build server is handled.
  package var preHandleNotificationFromBuildServer: (@Sendable (any NotificationType) async -> Void)?

  /// When running SourceKit-LSP in-process, allows the creator of `SourceKitLSPServer` to create a message handler that
  /// handles BSP requests instead of SourceKit-LSP creating build server as needed.
  package var injectBuildServer:
    (@Sendable (_ projectRoot: URL, _ connectionToSourceKitLSP: any Connection) async -> any Connection)?

  package init(
    preHandleRequest: (@Sendable (any RequestType) async -> Void)? = nil,
    preHandleNotificationFromBuildServer: (@Sendable (any NotificationType) async -> Void)? = nil,
    injectBuildServer: (
      @Sendable (_ projectRoot: URL, _ connectionToSourceKitLSP: any Connection) async -> any Connection
    )? = nil
  ) {
    self.preHandleRequest = preHandleRequest
    self.preHandleNotificationFromBuildServer = preHandleNotificationFromBuildServer
    self.injectBuildServer = injectBuildServer
  }
}
