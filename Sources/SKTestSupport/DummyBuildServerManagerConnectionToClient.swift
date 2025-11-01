//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerIntegration
import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol

package struct DummyBuildServerManagerConnectionToClient: BuildServerManagerConnectionToClient {
  package var clientSupportsWorkDoneProgress: Bool = false

  package init() {}

  package func waitUntilInitialized() async {}

  package func send(_ notification: some NotificationType) {}

  package func nextRequestID() -> RequestID {
    return .string(UUID().uuidString)
  }

  package func send<Request: RequestType>(
    _ request: Request,
    id: RequestID,
    reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
  ) {
    reply(.failure(ResponseError.unknown("Not implemented")))
  }

  package func watchFiles(_ fileWatchers: [FileSystemWatcher]) async {}

  func logMessageToIndexLog(message: String, type: WindowMessageType, structure: StructuredLogKind?) {}
}
