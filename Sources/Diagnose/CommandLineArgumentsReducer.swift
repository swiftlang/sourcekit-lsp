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

import Foundation

/// Reduces the compiler arguments needed to reproduce a sourcekitd crash.
class CommandLineArgumentReducer {
  /// The executor that is used to run a sourcekitd request and check whether it
  /// still crashes.
  private let sourcekitdExecutor: SourceKitRequestExecutor

  /// The file to which we write the reduced source code.
  private let temporarySourceFile: URL

  init(sourcekitdExecutor: SourceKitRequestExecutor) {
    self.sourcekitdExecutor = sourcekitdExecutor
    temporarySourceFile = FileManager.default.temporaryDirectory.appendingPathComponent("reduce.swift")
  }

  func logSuccessfulReduction(_ requestInfo: RequestInfo) {
    print("Reduced compiler arguments to \(requestInfo.compilerArgs.count)")
  }

  func run(initialRequestInfo: RequestInfo) async throws -> RequestInfo {
    try initialRequestInfo.fileContents.write(to: temporarySourceFile, atomically: true, encoding: .utf8)
    var requestInfo = initialRequestInfo

    var argumentIndexToRemove = requestInfo.compilerArgs.count - 1
    while argumentIndexToRemove >= 0 {
      var numberOfArgumentsToRemove = 1
      // If the argument is preceded by -Xswiftc or -Xcxx, we need to remove the `-X` flag as well.
      if argumentIndexToRemove - numberOfArgumentsToRemove >= 0
        && requestInfo.compilerArgs[argumentIndexToRemove - numberOfArgumentsToRemove].hasPrefix("-X")
      {
        numberOfArgumentsToRemove += 1
      }

      if let reduced = try await tryRemoving(
        (argumentIndexToRemove - numberOfArgumentsToRemove + 1)...argumentIndexToRemove,
        from: requestInfo
      ) {
        requestInfo = reduced
        argumentIndexToRemove -= numberOfArgumentsToRemove
        continue
      }

      // If removing the argument failed and the argument is preceded by an argument starting with `-`, try removing that as well.
      // E.g. removing `-F` followed by a search path.
      if argumentIndexToRemove - numberOfArgumentsToRemove >= 0
        && requestInfo.compilerArgs[argumentIndexToRemove - numberOfArgumentsToRemove].hasPrefix("-")
      {
        numberOfArgumentsToRemove += 1
      }

      // If the argument is preceded by -Xswiftc or -Xcxx, we need to remove the `-X` flag as well.
      if argumentIndexToRemove - numberOfArgumentsToRemove >= 0
        && requestInfo.compilerArgs[argumentIndexToRemove - numberOfArgumentsToRemove].hasPrefix("-X")
      {
        numberOfArgumentsToRemove += 1
      }

      if let reduced = try await tryRemoving(
        (argumentIndexToRemove - numberOfArgumentsToRemove + 1)...argumentIndexToRemove,
        from: requestInfo
      ) {
        requestInfo = reduced
        argumentIndexToRemove -= numberOfArgumentsToRemove
        continue
      }
      argumentIndexToRemove -= 1
    }

    return requestInfo
  }

  private func tryRemoving(
    _ argumentsToRemove: ClosedRange<Int>,
    from requestInfo: RequestInfo
  ) async throws -> RequestInfo? {
    var reducedRequestInfo = requestInfo
    reducedRequestInfo.compilerArgs.removeSubrange(argumentsToRemove)

    let result = try await sourcekitdExecutor.run(request: reducedRequestInfo.request(for: temporarySourceFile))
    if case .reproducesIssue = result {
      logSuccessfulReduction(reducedRequestInfo)
      return reducedRequestInfo
    } else {
      // The reduced request did not crash. We did not find a reduced test case, so return `nil`.
      return nil
    }
  }
}
