//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public import Testing

public func expectThrowsError<T>(
  _ expression: @autoclosure () async throws -> T,
  _ message: @autoclosure () -> String = "",
  sourceLocation: SourceLocation = #_sourceLocation,
  errorHandler: (_ error: any Error) -> Void = { _ in }
) async {
  do {
    _ = try await expression()
    Issue.record("Expression was expected to throw but did not throw", sourceLocation: sourceLocation)
  } catch {
    errorHandler(error)
  }
}
