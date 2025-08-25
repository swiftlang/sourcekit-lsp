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

import BuildServerIntegration
import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import SKLogging

extension BuildServerManager {
  /// Retrieves the name of the Swift module for a given target.
  ///
  /// **Note:** prefer using ``module(for:in:)`` over ths function. This function
  /// only exists for cases where you want the Swift module name of a target where
  /// you don't know one of its Swift document URIs in advance. E.g. when handling
  /// requests for Markdown/Tutorial files in DocC since they don't have compile
  /// commands that could be used to find the module name.
  ///
  /// - Parameter target: The build target identifier
  /// - Returns: The name of the Swift module or nil if it could not be determined
  func moduleName(for target: BuildTargetIdentifier) async -> String? {
    let sourceFiles =
      await orLog(
        "Failed to retreive source files from target \(target.uri)",
        { try await self.sourceFiles(in: [target]).flatMap(\.sources) }
      ) ?? []
    for sourceFile in sourceFiles {
      let language = await defaultLanguage(for: sourceFile.uri, in: target)
      guard language == .swift else {
        continue
      }
      if let moduleName = await moduleName(for: sourceFile.uri, in: target) {
        return moduleName
      }
    }
    return nil
  }

  /// Finds the SwiftDocC documentation catalog associated with a target, if any.
  ///
  /// - Parameter target: The build target identifier
  /// - Returns: The URL of the documentation catalog or nil if one could not be found
  func doccCatalog(for target: BuildTargetIdentifier) async -> URL? {
    let sourceFiles =
      await orLog(
        "Failed to retrieve source files from target \(target.uri)",
        { try await self.sourceFiles(in: [target]).flatMap(\.sources) }
      ) ?? []
    let catalogURLs = sourceFiles.compactMap { sourceItem -> URL? in
      guard sourceItem.dataKind == .sourceKit,
        let data = SourceKitSourceItemData(fromLSPAny: sourceItem.data),
        data.kind == .doccCatalog
      else {
        return nil
      }
      return sourceItem.uri.fileURL
    }.sorted(by: { $0.absoluteString < $1.absoluteString })
    if catalogURLs.count > 1 {
      logger.error("Multiple SwiftDocC catalogs found in build target \(target.uri)")
    }
    return catalogURLs.first
  }
}
