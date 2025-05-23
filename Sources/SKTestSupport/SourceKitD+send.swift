//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import Csourcekitd
package import SourceKitD

extension SourceKitD {
  /// Convenience overload of the `send` function for testing that doesn't restart sourcekitd if it does not respond
  /// and doesn't pass any file contents.
  package func send(
    _ requestUid: KeyPath<sourcekitd_api_requests, sourcekitd_api_uid_t>,
    _ request: SKDRequestDictionary,
    timeout: Duration = defaultTimeoutDuration
  ) async throws -> SKDResponseDictionary {
    return try await self.send(
      requestUid,
      request,
      timeout: timeout,
      restartTimeout: .seconds(60 * 60 * 24),
      documentUrl: nil,
      fileContents: nil
    )
  }
}
