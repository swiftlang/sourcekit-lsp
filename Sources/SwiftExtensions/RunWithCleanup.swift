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

#if swift(>=6.4)
#warning("Remove this in favor of SE-0493 (Support async calls in defer bodies) when possible")
#endif
/// Run `body` and always ensure that `cleanup` gets run, independently of whether `body` threw an error or returned a
/// value.
package func run<T>(
  _ body: () async throws -> T,
  cleanup: () async -> Void
) async throws -> T {
  do {
    let result = try await body()
    await cleanup()
    return result
  } catch {
    await cleanup()
    throw error
  }
}
