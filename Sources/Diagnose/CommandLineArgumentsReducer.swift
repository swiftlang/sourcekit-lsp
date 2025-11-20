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
@_spi(SourceKitLSP) import SKLogging

// MARK: - Entry point

extension RequestInfo {
  @MainActor
  func reduceCommandLineArguments(
    using executor: any SourceKitRequestExecutor,
    progressUpdate: (_ progress: Double, _ message: String) -> Void
  ) async throws -> RequestInfo {
    try await withoutActuallyEscaping(progressUpdate) { progressUpdate in
      let reducer = CommandLineArgumentReducer(sourcekitdExecutor: executor, progressUpdate: progressUpdate)
      return try await reducer.run(initialRequestInfo: self)
    }
  }
}

// MARK: - FileProducer

/// Reduces the compiler arguments needed to reproduce a sourcekitd crash.
private class CommandLineArgumentReducer {
  /// The executor that is used to run a sourcekitd request and check whether it
  /// still crashes.
  private let sourcekitdExecutor: any SourceKitRequestExecutor

  /// A callback to be called when the reducer has made progress reducing the request
  private let progressUpdate: (_ progress: Double, _ message: String) -> Void

  /// The number of command line arguments when the reducer was started.
  private var initialCommandLineCount: Int = 0

  init(
    sourcekitdExecutor: any SourceKitRequestExecutor,
    progressUpdate: @escaping (_ progress: Double, _ message: String) -> Void
  ) {
    self.sourcekitdExecutor = sourcekitdExecutor
    self.progressUpdate = progressUpdate
  }

  @MainActor
  func run(initialRequestInfo: RequestInfo) async throws -> RequestInfo {
    var requestInfo = initialRequestInfo
    requestInfo = try await reduce(initialRequestInfo: requestInfo, simultaneousRemove: 10)
    requestInfo = try await reduce(initialRequestInfo: requestInfo, simultaneousRemove: 1)
    return requestInfo
  }

  /// Reduce the command line arguments of the given `RequestInfo`.
  ///
  /// If `simultaneousRemove` is set, the reducer will try to remove that many arguments at once. This is useful to
  /// quickly remove multiple arguments from the request.
  @MainActor
  private func reduce(initialRequestInfo: RequestInfo, simultaneousRemove: Int) async throws -> RequestInfo {
    guard initialRequestInfo.compilerArgs.count > simultaneousRemove else {
      // Trying to remove more command line arguments than we have. This isn't going to work.
      return initialRequestInfo
    }

    var requestInfo = initialRequestInfo
    self.initialCommandLineCount = requestInfo.compilerArgs.count

    var argumentIndexToRemove = requestInfo.compilerArgs.count - 1
    while argumentIndexToRemove + 1 >= simultaneousRemove {
      defer {
        // argumentIndexToRemove can become negative by being decremented in the code below
        let progress = 1 - (Double(max(argumentIndexToRemove, 0)) / Double(initialCommandLineCount))
        progressUpdate(progress, "Reduced compiler arguments to \(requestInfo.compilerArgs.count)")
      }
      var numberOfArgumentsToRemove = simultaneousRemove
      // If the argument is preceded by -Xswiftc or -Xcxx, we need to remove the `-X` flag as well.
      if requestInfo.compilerArgs[safe: argumentIndexToRemove - numberOfArgumentsToRemove]?.hasPrefix("-X") ?? false {
        numberOfArgumentsToRemove += 1
      }

      let rangeToRemove = (argumentIndexToRemove - numberOfArgumentsToRemove + 1)...argumentIndexToRemove
      if let reduced = try await tryRemoving(rangeToRemove, from: requestInfo) {
        requestInfo = reduced
        argumentIndexToRemove -= numberOfArgumentsToRemove
        continue
      }

      // If removing the argument failed and the argument is preceded by an argument starting with `-`, try removing
      // that as well. E.g. removing `-F` followed by a search path.
      if requestInfo.compilerArgs[safe: argumentIndexToRemove - numberOfArgumentsToRemove]?.hasPrefix("-") ?? false {
        numberOfArgumentsToRemove += 1

        // If the argument is preceded by -Xswiftc or -Xcxx, we need to remove the `-X` flag as well.
        if requestInfo.compilerArgs[safe: argumentIndexToRemove - numberOfArgumentsToRemove]?.hasPrefix("-X") ?? false {
          numberOfArgumentsToRemove += 1
        }

        let rangeToRemove = (argumentIndexToRemove - numberOfArgumentsToRemove + 1)...argumentIndexToRemove
        if let reduced = try await tryRemoving(rangeToRemove, from: requestInfo) {
          requestInfo = reduced
          argumentIndexToRemove -= numberOfArgumentsToRemove
          continue
        }
      }

      argumentIndexToRemove -= simultaneousRemove
    }

    return requestInfo
  }

  @MainActor
  private func tryRemoving(
    _ argumentsToRemove: ClosedRange<Int>,
    from requestInfo: RequestInfo
  ) async throws -> RequestInfo? {
    logger.debug("Try removing the following compiler arguments:\n\(requestInfo.compilerArgs[argumentsToRemove])")
    var reducedRequestInfo = requestInfo
    reducedRequestInfo.compilerArgs.removeSubrange(argumentsToRemove)

    let result = try await sourcekitdExecutor.run(request: reducedRequestInfo)
    if case .reproducesIssue = result {
      logger.debug("Reduction successful")
      return reducedRequestInfo
    } else {
      // The reduced request did not crash. We did not find a reduced test case, so return `nil`.
      logger.debug("Reduction did not reproduce the issue")
      return nil
    }
  }
}

fileprivate extension Array {
  /// Access index in the array if it's in bounds or return `nil` if `index` is outside of the array's bounds.
  subscript(safe index: Int) -> Element? {
    if index < 0 || index >= count {
      return nil
    }
    return self[index]
  }
}
