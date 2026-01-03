//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) package import LanguageServerProtocol
import SwiftExtensions
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

extension Connection {
  /// Send the given request to the connection and await its result.
  ///
  /// This method automatically sends a `CancelRequestNotification` to the
  /// connection if the task it is executing in is being cancelled.
  ///
  /// - Warning: Because this message is `async`, it does not provide any ordering
  ///   guarantees. If you need to guarantee that messages are sent in-order
  ///   use the version with a completion handler.
  // Disfavor this over Connection.send implemented in swift-tools-protocols by https://github.com/swiftlang/swift-tools-protocols/pull/28
  // TODO: Remove this file once we have updated the swift-tools-protocols dependency to include #28
  @_disfavoredOverload
  package func send<R: RequestType>(_ request: R) async throws -> R.Response {
    return try await withCancellableCheckedThrowingContinuation { continuation in
      return self.send(request) { result in
        continuation.resume(with: result)
      }
    } cancel: { requestID in
      self.send(CancelRequestNotification(id: requestID))
    }
  }
}
