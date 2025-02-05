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

import Synchronization

#if compiler(>=6)
package import LanguageServerProtocol
import SwiftExtensions
#else
import LanguageServerProtocol
import SwiftExtensions
#endif

/// A request and a callback that returns the request's reply
package final class RequestAndReply<Params: RequestType>: Sendable {
  package let params: Params
  private let replyBlock: @Sendable (LSPResult<Params.Response>) -> Void

  /// Whether a reply has been made. Every request must reply exactly once.
  private let replied: Atomic<Bool> = Atomic(false)

  package init(_ request: Params, reply: @escaping @Sendable (LSPResult<Params.Response>) -> Void) {
    self.params = request
    self.replyBlock = reply
  }

  deinit {
    precondition(replied.load(ordering: .sequentiallyConsistent), "request never received a reply")
  }

  /// Call the `replyBlock` with the result produced by the given closure.
  package func reply(_ body: @Sendable () async throws -> Params.Response) async {
    precondition(!replied.load(ordering: .sequentiallyConsistent), "replied to request more than once")
    replied.store(true, ordering: .sequentiallyConsistent)
    do {
      replyBlock(.success(try await body()))
    } catch {
      replyBlock(.failure(ResponseError(error)))
    }
  }
}
