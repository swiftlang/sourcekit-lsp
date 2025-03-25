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

import BuildServerProtocol
package import BuildSystemIntegration
package import Foundation
package import LanguageServerProtocol

package extension BuildSystemManager {
  func moduleName(for document: DocumentURI) async -> String? {
    guard let target = await canonicalTarget(for: document) else {
      return nil
    }
    let sourceFiles = (try? await sourceFiles(in: [target]).flatMap(\.sources)) ?? []
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

  func doccCatalog(for document: DocumentURI) async -> URL? {
    guard let target = await canonicalTarget(for: document) else {
      return nil
    }
    let sourceFiles = (try? await sourceFiles(in: [target]).flatMap(\.sources)) ?? []
    let catalogURLs = sourceFiles.compactMap { sourceItem -> URL? in
      guard sourceItem.dataKind == .sourceKit,
        let data = SourceKitSourceItemData(fromLSPAny: sourceItem.data),
        data.kind == .doccCatalog
      else {
        return nil
      }
      return sourceItem.uri.fileURL
    }.sorted(by: { $0.absoluteString >= $1.absoluteString })
    return catalogURLs.first
  }
}
