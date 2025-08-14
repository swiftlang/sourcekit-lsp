//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import IndexStoreDB
package import LanguageServerProtocol
import SourceKitLSP

extension SwiftLanguageService {
  package func symbolGraph(
    forOnDiskContentsOf symbolDocumentUri: DocumentURI,
    at location: SymbolLocation
  ) async throws -> String? {
    return try await withSnapshotFromDiskOpenedInSourcekitd(
      uri: symbolDocumentUri,
      fallbackSettingsAfterTimeout: false
    ) { snapshot, compileCommand in
      try await cursorInfo(
        snapshot,
        compileCommand: compileCommand,
        Range(snapshot.position(of: location)),
        includeSymbolGraph: true
      ).symbolGraph
    }
  }
}
