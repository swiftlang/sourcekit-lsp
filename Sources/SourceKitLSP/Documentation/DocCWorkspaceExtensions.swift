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
import BuildSystemIntegration
import Foundation
import LanguageServerProtocol

extension Workspace {
  private var documentationManager: DocumentationManager {
    get throws {
      guard let sourceKitLSPServer else {
        throw ResponseError.unknown("Connection to the editor closed")
      }
      return sourceKitLSPServer.documentationManager
    }
  }

  func findModuleName(for document: DocumentURI) async -> String? {
    guard let target = await buildSystemManager.canonicalTarget(for: document) else {
      return nil
    }
    let sourceFiles = (try? await buildSystemManager.sourceFiles(in: [target]).flatMap(\.sources)) ?? []
    for sourceFile in sourceFiles {
      let language = await buildSystemManager.defaultLanguage(for: sourceFile.uri, in: target)
      guard language == .swift else {
        continue
      }
      if let moduleName = await buildSystemManager.moduleName(for: sourceFile.uri, in: target) {
        return moduleName
      }
    }
    return nil
  }

  func findDocCCatalog(for document: DocumentURI) async -> URL? {
    guard let target = await buildSystemManager.canonicalTarget(for: document) else {
      return nil
    }
    let sourceFiles = (try? await buildSystemManager.sourceFiles(in: [target]).flatMap(\.sources)) ?? []
    return sourceFiles.compactMap(\.uri.fileURL?.doccCatalogURL).first
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
