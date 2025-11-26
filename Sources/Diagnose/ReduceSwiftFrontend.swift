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

@MainActor
package func reduceFrontendIssue(
  frontendArgs: [String],
  using executor: any SourceKitRequestExecutor,
  progressUpdate: (_ progress: Double, _ message: String) -> Void
) async throws -> RequestInfo {
  let requestInfo = try RequestInfo(frontendArgs: frontendArgs)
  let initialResult = try await executor.run(request: requestInfo)
  guard case .reproducesIssue = initialResult else {
    throw GenericError("Unable to reproduce the swift-frontend issue")
  }
  let mergedSwiftFilesRequestInfo = try await requestInfo.mergeSwiftFiles(using: executor) { progress, message in
    progressUpdate(0, message)
  }
  guard let mergedSwiftFilesRequestInfo else {
    throw GenericError("Merging all .swift files did not reproduce the issue. Unable to reduce it.")
  }
  return try await mergedSwiftFilesRequestInfo.reduce(using: executor, progressUpdate: progressUpdate)
}
