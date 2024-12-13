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

/// Represents url of generated interface reference document.

package struct GeneratedInterfaceDocumentURLData: Hashable, ReferenceURLData {
  package static let documentType = "generated-swift-interface"

  private struct Parameters {
    static let moduleName = "moduleName"
    static let groupName = "groupName"
    static let sourcekitdDocumentName = "sourcekitdDocument"
    static let buildSettingsFrom = "buildSettingsFrom"
  }

  /// The module that should be shown in this generated interface.
  let moduleName: String

  /// The group that should be shown in this generated interface, if applicable.
  let groupName: String?

  /// The name by which this document is referred to in sourcekitd.
  let sourcekitdDocumentName: String

  /// The document from which the build settings for the generated interface should be inferred.
  let buildSettingsFrom: DocumentURI

  var displayName: String {
    if let groupName {
      return "\(moduleName).\(groupName.replacing("/", with: ".")).swiftinterface"
    }
    return "\(moduleName).swiftinterface"
  }

  var queryItems: [URLQueryItem] {
    var result = [
      URLQueryItem(name: Parameters.moduleName, value: moduleName)
    ]
    if let groupName {
      result.append(URLQueryItem(name: Parameters.groupName, value: groupName))
    }
    result += [
      URLQueryItem(name: Parameters.sourcekitdDocumentName, value: sourcekitdDocumentName),
      URLQueryItem(name: Parameters.buildSettingsFrom, value: buildSettingsFrom.stringValue),
    ]
    return result
  }

  var uri: DocumentURI {
    get throws {
      try ReferenceDocumentURL.generatedInterface(self).uri
    }
  }

  init(moduleName: String, groupName: String?, sourcekitdDocumentName: String, primaryFile: DocumentURI) {
    self.moduleName = moduleName
    self.groupName = groupName
    self.sourcekitdDocumentName = sourcekitdDocumentName
    self.buildSettingsFrom = primaryFile
  }

  init(queryItems: [URLQueryItem]) throws {
    guard let moduleName = queryItems.last(where: { $0.name == Parameters.moduleName })?.value,
      let sourcekitdDocumentName = queryItems.last(where: { $0.name == Parameters.sourcekitdDocumentName })?.value,
      let primaryFile = queryItems.last(where: { $0.name == Parameters.buildSettingsFrom })?.value
    else {
      throw ReferenceDocumentURLError(description: "Invalid queryItems for generated interface reference document url")
    }

    self.moduleName = moduleName
    self.groupName = queryItems.last(where: { $0.name == Parameters.groupName })?.value
    self.sourcekitdDocumentName = sourcekitdDocumentName
    self.buildSettingsFrom = try DocumentURI(string: primaryFile)
  }
}
