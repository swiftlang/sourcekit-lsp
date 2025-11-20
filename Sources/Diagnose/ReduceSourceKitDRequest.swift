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

extension RequestInfo {
  /// Reduce the input file of this request and the command line arguments.
  @MainActor
  func reduce(
    using executor: any SourceKitRequestExecutor,
    progressUpdate: (_ progress: Double, _ message: String) -> Void
  ) async throws -> RequestInfo {
    var requestInfo = self

    // How much time of the reduction is expected to be spent reducing the source compared to command line argument
    // reduction.
    let sourceReductionPercentage = 0.7

    requestInfo = try await requestInfo.reduceInputFile(using: executor) { progress, message in
      let progress = progress * sourceReductionPercentage
      progressUpdate(progress, message)
    }
    requestInfo = try await requestInfo.reduceCommandLineArguments(using: executor) { progress, message in
      let progress = sourceReductionPercentage + progress * (1 - sourceReductionPercentage)
      progressUpdate(progress, message)
    }
    return requestInfo
  }
}
