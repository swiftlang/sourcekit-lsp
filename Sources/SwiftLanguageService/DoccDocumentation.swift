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
import IndexStoreDB
package import LanguageServerProtocol
import SKLogging
import SemanticIndex
import SourceKitLSP
import SwiftExtensions
import SwiftSyntax

#if canImport(DocCDocumentation)
import DocCDocumentation
#endif

extension SwiftLanguageService {
  package func doccDocumentation(_ req: DoccDocumentationRequest) async throws -> DoccDocumentationResponse {
    throw ResponseError.requestNotImplemented(DoccDocumentationRequest.self)
  }
}
