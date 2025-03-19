//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import Foundation
@preconcurrency package import IndexStoreDB
package import LanguageServerProtocol
package import SemanticIndex

/// An actor that can be used to interface with SwiftDocC
package protocol DocCDocumentationManager: Actor {
  func getRenderingSupport() -> DocCDocumentationManagerWithRendering?
}

/// An actor that can be used to render SwiftDocC documentation
package protocol DocCDocumentationManagerWithRendering: DocCDocumentationManager {
  func filesDidChange(_: [FileEvent]) async

  func catalogIndex(for: URL) async throws -> DocCCatalogIndex

  func symbolLink(string: String) -> DocCSymbolLink?

  func symbolLink(forUSR: String, in: CheckedIndex) -> DocCSymbolLink?

  func primaryDefinitionOrDeclarationOccurrence(
    ofDocCSymbolLink: DocCSymbolLink,
    in: CheckedIndex
  ) -> SymbolOccurrence?

  func renderDocCDocumentation(
    symbolUSR: String?,
    symbolGraph: String?,
    overrideDocComments: [String]?,
    markupFile: String?,
    tutorialFile: String?,
    moduleName: String?,
    catalogURL: URL?
  ) async throws -> DoccDocumentationResponse
}

extension DocCDocumentationManagerWithRendering {
  package func renderDocCDocumentation(
    symbolUSR: String? = nil,
    symbolGraph: String? = nil,
    overrideDocComments: [String]? = nil,
    markupFile: String? = nil,
    tutorialFile: String? = nil,
    moduleName: String?,
    catalogURL: URL?
  ) async throws -> DoccDocumentationResponse {
    try await renderDocCDocumentation(
      symbolUSR: symbolUSR,
      symbolGraph: symbolGraph,
      overrideDocComments: overrideDocComments,
      markupFile: markupFile,
      tutorialFile: tutorialFile,
      moduleName: moduleName,
      catalogURL: catalogURL
    )
  }
}

/// Creates a new ``DocCDocumentationManager`` that can be used to interface with SwiftDocC.
///
/// - Returns: An instance of ``DocCDocumentationManager``
package func createDocCDocumentationManager() -> any DocCDocumentationManager {
  DocCDocumentationManagerImpl()
}
