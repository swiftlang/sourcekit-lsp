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
import SKLogging

#if compiler(>=6)
package import LanguageServerProtocol
#else
import LanguageServerProtocol
#endif

extension SwiftLanguageService {
  package func openGeneratedInterface(
    document: DocumentURI,
    moduleName: String,
    groupName: String?,
    symbolUSR symbol: String?
  ) async throws -> GeneratedInterfaceDetails? {
    let urlData = GeneratedInterfaceDocumentURLData(
      moduleName: moduleName,
      groupName: groupName,
      sourcekitdDocumentName: "\(moduleName)-\(UUID())",
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

    if case .dictionary(let experimentalCapabilities) = self.capabilityRegistry.clientCapabilities.experimental,
      case .bool(true) = experimentalCapabilities["workspace/getReferenceDocument"]
    {
      return GeneratedInterfaceDetails(uri: try urlData.uri, position: position)
    }
    let interfaceFilePath = self.generatedInterfacesPath.appendingPathComponent(urlData.displayName)
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
