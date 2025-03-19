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
    return sourceFiles.compactMap(\.uri.fileURL?.doccCatalogURL).first
  }
}

package extension URL {
  var doccCatalogURL: URL? {
    var pathComponents = self.pathComponents
    var result = self
    while let lastPathComponent = pathComponents.last {
      if lastPathComponent.hasSuffix(".docc") {
        return result
      }
      pathComponents.removeLast()
      result.deleteLastPathComponent()
    }
    return nil
  }
}
