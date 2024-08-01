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

  var url: URL {
    get throws {
      switch self {
      case let .macroExpansion(data):
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = MacroExpansionReferenceDocumentURLData.documentType
        components.path = "/\(data.displayName)"
        components.queryItems = data.queryItems

        guard let url = components.url else {
          throw ReferenceDocumentURLError(
            description: "Unable to create URL for macro expansion reference document"
          )
        }

        return url
      }
    }
  }

  init(from uri: DocumentURI) throws {
    try self.init(from: uri.arbitrarySchemeURL)
  }

  init(from url: URL) throws {
    guard url.scheme == Self.scheme else {
      throw ReferenceDocumentURLError(description: "Invalid Scheme for reference document")
    }

    let documentType = url.host(percentEncoded: false)

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
    case nil:
      throw ReferenceDocumentURLError(
        description: "Bad URL for reference document: \(url)"
      )
    default:
      throw ReferenceDocumentURLError(
        description: "Invalid document type in URL for reference document: \(documentType)"
      )
    }
  }

  /// The URI of the document from which this reference document was derived. This is used to determine the
  /// workspace and language service that is used to generate the reference document.
  var primaryFile: DocumentURI {
    switch self {
    case let .macroExpansion(data):
      return data.primaryFile
    }
  }
}

package struct ReferenceDocumentURLError: Error, CustomStringConvertible {
  package var description: String

  init(description: String) {
    self.description = description
  }
}
