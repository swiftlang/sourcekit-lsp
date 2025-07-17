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

import IndexStoreDB
import LanguageServerProtocol
import SKLogging

/// Registry in which conformers to `LanguageService` can be registered to server semantic functionality for a set of
/// languages.
package struct LanguageServiceRegistry {
  private var byLanguage: [Language: LanguageService.Type] = [:]

  package init() {
    self.register(ClangLanguageService.self, for: [.c, .cpp, .objective_c, .objective_cpp])
    self.register(SwiftLanguageService.self, for: [.swift])
    self.register(DocumentationLanguageService.self, for: [.markdown, .tutorial])
  }

  private mutating func register(_ languageService: LanguageService.Type, for languages: [Language]) {
    for language in languages {
      if let existingLanguageService = byLanguage[language] {
        logger.fault(
          "Cannot register \(languageService) for \(language, privacy: .public) because \(existingLanguageService) is already registered"
        )
        continue
      }
      byLanguage[language] = languageService
    }
  }

  func languageService(for language: Language) -> LanguageService.Type? {
    return byLanguage[language]
  }
}
