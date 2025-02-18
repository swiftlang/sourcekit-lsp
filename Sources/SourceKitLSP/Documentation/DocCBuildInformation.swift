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

#if canImport(SwiftDocC)
import BuildServerProtocol
import Foundation
import LanguageServerProtocol

struct DocCBuildInformation {
  let catalogURL: URL?
  let moduleName: String?
  let catalogIndex: DocCCatalogIndex?

  init(catalogURL: URL? = nil, moduleName: String? = nil, catalogIndex: DocCCatalogIndex? = nil) {
    self.catalogURL = catalogURL
    self.moduleName = moduleName
    self.catalogIndex = catalogIndex
  }
}

extension Workspace {
  private var documentationManager: DocumentationManager {
    get throws {
      guard let sourceKitLSPServer else {
        throw ResponseError.unknown("Connection to the editor closed")
      }
      return sourceKitLSPServer.documentationManager
    }
  }

  func doccBuildInformation(for document: DocumentURI) async -> DocCBuildInformation {
    let target = await buildSystemManager.canonicalTarget(for: document)
    guard let target else {
      return DocCBuildInformation()
    }
    let sourceFiles = (try? await buildSystemManager.sourceFiles(in: [target]).flatMap(\.sources)) ?? []
    var moduleName: String? = nil
    let catalogURL: URL? = sourceFiles.compactMap(\.uri.fileURL?.doccCatalogURL).first
    for sourceFile in sourceFiles {
      let language = await buildSystemManager.defaultLanguage(for: sourceFile.uri, in: target)
      guard language == .swift else {
        continue
      }
      moduleName = await buildSystemManager.moduleName(for: sourceFile.uri, in: target)
      if moduleName != nil {
        break
      }
    }
    var catalogIndex: DocCCatalogIndex? = nil
    if let catalogURL {
      catalogIndex = try? await documentationManager.catalogIndex(for: catalogURL, moduleName: moduleName)
    }
    return DocCBuildInformation(catalogURL: catalogURL, moduleName: moduleName, catalogIndex: catalogIndex)
  }
}

extension URL {
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
#endif
