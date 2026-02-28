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

import ClangLanguageService
@_spi(SourceKitLSP) import LanguageServerProtocol
package import SourceKitLSP
import SwiftLanguageService

#if canImport(DocumentationLanguageService)
import DocumentationLanguageService
#endif

extension LanguageServiceRegistry {
  /// All types conforming to `LanguageService` that are known at compile time.
  package static let staticallyKnownServices = {
    var registry = LanguageServiceRegistry()
    registry.register(ClangLanguageService.self, for: [.c, .cpp, .objective_c, .objective_cpp])
    #if canImport(DocumentationLanguageService)
    registry.register(DocumentationLanguageService.self, for: [.markdown, .tutorial, .swift])
    #endif
    registry.register(SwiftLanguageService.self, for: [.swift])
    return registry
  }()
}
