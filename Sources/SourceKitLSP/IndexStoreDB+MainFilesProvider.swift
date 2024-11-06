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

#if compiler(>=6)
import BuildSystemIntegration
import Foundation
import IndexStoreDB
package import LanguageServerProtocol
import SKLogging
import SemanticIndex
import SwiftExtensions
#else
import BuildSystemIntegration
import Foundation
import IndexStoreDB
import LanguageServerProtocol
import SKLogging
import SemanticIndex
import SwiftExtensions
#endif

extension UncheckedIndex {
  package func mainFilesContainingFile(_ uri: DocumentURI) -> Set<DocumentURI> {
    let mainFiles: Set<DocumentURI>
    if let filePath = orLog("File path to get main files", { try uri.fileURL?.filePath }) {
      let mainFilePaths = Set(self.underlyingIndexStoreDB.mainFilesContainingFile(path: filePath))
      mainFiles = Set(
        mainFilePaths
          .filter { FileManager.default.fileExists(atPath: $0) }
          .map({ DocumentURI(filePath: $0, isDirectory: false) })
      )
    } else {
      mainFiles = []
    }
    logger.info("mainFilesContainingFile(\(uri.forLogging)) -> \(mainFiles)")
    return mainFiles
  }
}

extension UncheckedIndex: BuildSystemIntegration.MainFilesProvider {}
