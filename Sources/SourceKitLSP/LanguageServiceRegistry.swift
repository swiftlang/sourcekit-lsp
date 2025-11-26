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
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging

/// Wrapper around `LanguageService.Type`, making it conform to `Hashable`.
struct LanguageServiceType: Hashable {
  let type: any LanguageService.Type

  init(_ type: any LanguageService.Type) {
    self.type = type
  }

  static func == (lhs: LanguageServiceType, rhs: LanguageServiceType) -> Bool {
    return ObjectIdentifier(lhs.type) == ObjectIdentifier(rhs.type)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(type))
  }
}

/// Registry in which conformers to `LanguageService` can be registered to server semantic functionality for a set of
/// languages.
package struct LanguageServiceRegistry {
  private var byLanguage: [Language: [LanguageServiceType]] = [:]

  package init() {}

  package mutating func register(_ languageService: any LanguageService.Type, for languages: [Language]) {
    for language in languages {
      let services = byLanguage[language] ?? []
      if services.contains(LanguageServiceType(languageService)) {
        logger.fault("\(languageService) already registered for \(language, privacy: .public)")
        continue
      }
      byLanguage[language, default: []].append(LanguageServiceType(languageService))
    }
  }

  /// The language services that can handle a document of the given language.
  ///
  /// Multiple language services may be able to handle a document. Depending on the use case, callers need to combine
  /// the results of the language services.
  /// If it is possible to merge the results of the language service (eg. combining code actions from multiple language
  /// services), that's the preferred choice.
  /// Otherwise the language services occurring early in the array should be given precedence and the results of the
  /// first language service that produces some should be returned.
  func languageServices(for language: Language) -> [any LanguageService.Type] {
    return byLanguage[language]?.map(\.type) ?? []
  }

  /// All language services that are registered in the registry.
  var languageServices: Set<LanguageServiceType> {
    return Set(byLanguage.values.flatMap { $0 })
  }
}
