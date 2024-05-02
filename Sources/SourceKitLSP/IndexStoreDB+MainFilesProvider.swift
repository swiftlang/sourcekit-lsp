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

import Foundation
import LSPLogging
import LanguageServerProtocol
import SKCore
import SemanticIndex

extension UncheckedIndex {
  public func mainFilesContainingFile(_ uri: DocumentURI) -> Set<DocumentURI> {
    let mainFiles: Set<DocumentURI>
    if let url = uri.fileURL {
      let mainFilePaths = Set(self.underlyingIndexStoreDB.mainFilesContainingFile(path: url.path))
      mainFiles = Set(
        mainFilePaths
          .filter { FileManager.default.fileExists(atPath: $0) }
          .map({ DocumentURI(URL(fileURLWithPath: $0, isDirectory: false)) })
      )
    } else {
      mainFiles = []
    }
    logger.info("mainFilesContainingFile(\(uri.forLogging)) -> \(mainFiles)")
    return mainFiles
  }
}

#if compiler(<5.11)
extension UncheckedIndex: MainFilesProvider {}
#else
extension UncheckedIndex: @retroactive MainFilesProvider {}
#endif
