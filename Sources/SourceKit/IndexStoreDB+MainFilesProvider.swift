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

import IndexStoreDB
import LanguageServerProtocol
import SKCore

extension IndexStoreDB: MainFilesProvider {
  public func mainFilesContainingFile(_ uri: DocumentURI) -> Set<DocumentURI> {
    return Set(
      self.mainFilesContainingFile(path: uri.pseudoPath)
        .lazy.map({ DocumentURI(URL(fileURLWithPath: $0)) }))
  }
}
