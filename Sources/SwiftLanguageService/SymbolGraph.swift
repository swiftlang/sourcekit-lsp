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

import BuildServerIntegration
import Foundation
package import IndexStoreDB
import LanguageServerProtocol
import SKLogging
import SKUtilities
package import SourceKitLSP
import SwiftExtensions

extension SwiftLanguageService {
  package func symbolGraphForDocumentOnDisk(
    at location: SymbolLocation,
    manager: OnDiskDocumentManager
  ) async throws -> String? {
    let snapshot = try await manager.open(uri: location.documentUri, language: .swift)
    let patchedCompileCommand: SwiftCompileCommand? =
      if let buildSettings = await self.buildSettings(
        for: location.documentUri,
        fallbackAfterTimeout: false
      ) {
        SwiftCompileCommand(buildSettings.patching(newFile: snapshot.uri, originalFile: location.documentUri))
      } else {
        nil
      }

    return try await cursorInfo(
      snapshot,
      compileCommand: patchedCompileCommand,
      Range(snapshot.position(of: location)),
      includeSymbolGraph: true
    ).symbolGraph
  }
}
