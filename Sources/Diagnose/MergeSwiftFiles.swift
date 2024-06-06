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
import LSPLogging

extension RequestInfo {
  /// Check if the issue reproduces when merging all `.swift` input files into a single file.
  ///
  /// Returns `nil` if the issue didn't reproduce with all `.swift` files merged.
  @MainActor
  func mergeSwiftFiles(
    using executor: SourceKitRequestExecutor,
    progressUpdate: (_ progress: Double, _ message: String) -> Void
  ) async throws -> RequestInfo? {
    let swiftFilePaths = compilerArgs.filter { $0.hasSuffix(".swift") }
    let mergedFile = try swiftFilePaths.map { try String(contentsOfFile: $0) }.joined(separator: "\n\n\n\n")

    progressUpdate(0, "Merging all .swift files into a single file")

    let compilerArgs = compilerArgs.filter { $0 != "-primary-file" && !$0.hasSuffix(".swift") } + ["$FILE"]
    let mergedRequestInfo = RequestInfo(
      requestTemplate: requestTemplate,
      offset: offset,
      compilerArgs: compilerArgs,
      fileContents: mergedFile
    )

    let result = try await executor.run(request: mergedRequestInfo)
    if case .reproducesIssue = result {
      logger.debug("Successfully merged all .swift input files")
      return mergedRequestInfo
    } else {
      logger.debug("Merging .swift files did not reproduce the issue")
      return nil
    }
  }
}
