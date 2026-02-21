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

import BuildServerIntegration
import Foundation
import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
import SemanticIndex
import SwiftExtensions

extension UncheckedIndex: BuildServerIntegration.MainFilesProvider {
  /// - Important: This may return realpaths when the build server might not be using realpaths. Use
  ///   `BuildServerManager.mainFiles(containing:)` to work around that problem.
  package func mainFiles(containing uri: DocumentURI, crossLanguage: Bool) -> Set<DocumentURI> {
    let mainFiles: Set<DocumentURI>
    if let filePath = orLog("File path to get main files", { try uri.fileURL?.filePath }) {
      guard let underlyingIndexStoreDB = self.underlyingIndexStoreDB else {
        logger.error("Not checking main files for URI because index has been closed")
        return []
      }
      let mainFilePaths = underlyingIndexStoreDB.mainFilesContainingFile(
        path: filePath,
        crossLanguage: crossLanguage
      )
      mainFiles = Set(
        mainFilePaths
          .filter { FileManager.default.fileExists(atPath: $0) }
          .map({ DocumentURI(filePath: $0, isDirectory: false) })
      )
    } else {
      mainFiles = []
    }
    logger.info("Main files for \(uri.forLogging): \(mainFiles)")
    return mainFiles
  }
}
