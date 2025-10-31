//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging
package import SourceKitLSP

extension SwiftLanguageService {
  package func openGeneratedInterface(
    document: DocumentURI,
    moduleName: String,
    groupName: String?,
    symbolUSR symbol: String?
  ) async throws -> GeneratedInterfaceDetails? {
    // Include build settings context to distinguish different versions/configurations
    let buildSettingsFileHash = "\(abs(document.buildSettingsFile.stringValue.hashValue))"
    let sourcekitdDocumentName = [moduleName, groupName, buildSettingsFileHash].compactMap(\.self)
      .joined(separator: ".")

    let urlData = GeneratedInterfaceDocumentURLData(
      moduleName: moduleName,
      groupName: groupName,
      sourcekitdDocumentName: sourcekitdDocumentName,
      primaryFile: document
    )
    let position: Position? =
      if let symbol {
        await orLog("Getting position of USR") {
          try await generatedInterfaceManager.position(ofUsr: symbol, in: urlData)
        }
      } else {
        nil
      }

    if self.capabilityRegistry.clientHasExperimentalCapability(GetReferenceDocumentRequest.method) {
      return GeneratedInterfaceDetails(uri: try urlData.uri, position: position)
    }
    let interfaceFilePath = self.generatedInterfacesPath
      .appending(components: buildSettingsFileHash, urlData.displayName)
    try FileManager.default.createDirectory(
      at: interfaceFilePath.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try await generatedInterfaceManager.snapshot(of: urlData).text.write(
      to: interfaceFilePath,
      atomically: true,
      encoding: String.Encoding.utf8
    )
    return GeneratedInterfaceDetails(
      uri: DocumentURI(interfaceFilePath),
      position: position
    )
  }
}
