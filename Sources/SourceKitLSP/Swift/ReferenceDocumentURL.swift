//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol

protocol ReferenceURLData {
  static var documentType: String { get }
  var displayName: String { get }
  var queryItems: [URLQueryItem] { get }
}

/// A Reference Document is a document whose url scheme is `sourcekit-lsp:` and whose content can only be retrieved
/// using `GetReferenceDocumentRequest`. The enum represents a specific type of reference document and its
/// associated value represents the data necessary to generate the document's contents and its url
///
/// The `url` will be of the form: `sourcekit-lsp://<document-type>/<display-name>?<parameters>`
/// Here,
///  - The `<document-type>` denotes the kind of the content present in the reference document
///  - The `<parameters>` denotes the parameter-value pairs such as "p1=v1&p2=v2&..." needed to generate
/// the content of the reference document.
///  - The `<display-name>` is the displayed file name of the reference document. It doesn't involve in generating
/// the content of the reference document.
package enum ReferenceDocumentURL {
  package static let scheme = "sourcekit-lsp"

  case macroExpansion(MacroExpansionReferenceDocumentURLData)
  case generatedInterface(GeneratedInterfaceDocumentURLData)

  var url: URL {
    get throws {
      let data: ReferenceURLData =
        switch self {
        case .macroExpansion(let data): data
        case .generatedInterface(let data): data
        }

      var components = URLComponents()
      components.scheme = Self.scheme
      components.host = type(of: data).documentType
      components.path = "/\(data.displayName)"
      components.queryItems = data.queryItems

      guard let url = components.url else {
        throw ReferenceDocumentURLError(description: "Unable to create URL for reference document")
      }

      return url
    }
  }

  var uri: DocumentURI {
    get throws {
      DocumentURI(try url)
    }
  }

  init(from uri: DocumentURI) throws {
    try self.init(from: uri.arbitrarySchemeURL)
  }

  init(from url: URL) throws {
    guard url.scheme == Self.scheme else {
      throw ReferenceDocumentURLError(description: "Invalid Scheme for reference document")
    }

    let documentType = url.host

    switch documentType {
    case MacroExpansionReferenceDocumentURLData.documentType:
      guard let queryItems = URLComponents(string: url.absoluteString)?.queryItems else {
        throw ReferenceDocumentURLError(
          description: "No queryItems passed for macro expansion reference document: \(url)"
        )
      }

      let macroExpansionURLData = try MacroExpansionReferenceDocumentURLData(
        displayName: url.lastPathComponent,
        queryItems: queryItems
      )
      self = .macroExpansion(macroExpansionURLData)
    case GeneratedInterfaceDocumentURLData.documentType:
      guard let queryItems = URLComponents(string: url.absoluteString)?.queryItems else {
        throw ReferenceDocumentURLError(
          description: "No queryItems passed for generated interface reference document: \(url)"
        )
      }

      let macroExpansionURLData = try GeneratedInterfaceDocumentURLData(queryItems: queryItems)
      self = .generatedInterface(macroExpansionURLData)
    case nil:
      throw ReferenceDocumentURLError(
        description: "Bad URL for reference document: \(url)"
      )
    case let documentType?:
      throw ReferenceDocumentURLError(
        description: "Invalid document type in URL for reference document: \(documentType)"
      )
    }
  }

  /// The path that should be passed as `keys.sourcefile` to sourcekitd in conjunction with a `keys.primaryFile`.
  ///
  /// For macro expansions, this is the buffer name that the URI references.
  var sourcekitdSourceFile: String {
    switch self {
    case .macroExpansion(let data): return data.bufferName
    case .generatedInterface(let data): return data.sourcekitdDocumentName
    }
  }

  /// The file that should be used to retrieve build settings for this reference document.
  var buildSettingsFile: DocumentURI {
    switch self {
    case .macroExpansion(let data): return data.primaryFile
    case .generatedInterface(let data): return data.buildSettingsFrom
    }
  }

  var primaryFile: DocumentURI? {
    switch self {
    case .macroExpansion(let data): return data.primaryFile
    case .generatedInterface(let data): return data.buildSettingsFrom.primaryFile
    }
  }
}

extension DocumentURI {
  /// The path that should be passed as `keys.sourcefile` to sourcekitd in conjunction with a `keys.primaryFile`.
  ///
  /// For normal document URIs, this is the pseudo path of this URI. For macro expansions, this is the buffer name
  /// that the URI references.
  var sourcekitdSourceFile: String {
    if let referenceDocument = try? ReferenceDocumentURL(from: self) {
      referenceDocument.sourcekitdSourceFile
    } else {
      self.pseudoPath
    }
  }

  /// If this is a URI to a reference document, the URI of the source file from which this reference document was
  /// derived.
  ///
  /// The primary file is used to determine the workspace and language service that is used to generate the reference
  /// document as well as getting the reference document's build settings.
  var primaryFile: DocumentURI? {
    if let referenceDocument = try? ReferenceDocumentURL(from: self) {
      return referenceDocument.primaryFile
    }
    return nil
  }

  /// The file that should be used to retrieve build settings for this reference document.
  var buildSettingsFile: DocumentURI {
    if let referenceDocument = try? ReferenceDocumentURL(from: self) {
      return referenceDocument.buildSettingsFile
    }
    return self
  }
}

package struct ReferenceDocumentURLError: Error, CustomStringConvertible {
  package var description: String

  init(description: String) {
    self.description = description
  }
}
