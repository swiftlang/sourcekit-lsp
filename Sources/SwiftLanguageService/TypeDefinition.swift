//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import IndexStoreDB
@_spi(SourceKitLSP) package import LanguageServerProtocol
import SemanticIndex
import SourceKitD
import SourceKitLSP

extension SwiftLanguageService {
  /// Handles the textDocument/typeDefinition request.
  ///
  /// Given a source location, finds the type of the symbol at that position
  /// and returns the location of that type's definition.
  package func typeDefinition(_ request: TypeDefinitionRequest) async throws -> LocationsOrLocationLinksResponse? {
    let uri = request.textDocument.uri
    let position = request.position

    guard let location = try await lookupTypeDefinitionLocation(uri: uri, position: position) else {
      return nil
    }

    return .locations([location])
  }
}
