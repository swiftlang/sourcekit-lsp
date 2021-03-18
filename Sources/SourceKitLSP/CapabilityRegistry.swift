//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

/// A class which tracks the client's capabilities as well as our dynamic
/// capability registrations in order to avoid registering conflicting
/// capabilities.
public final class CapabilityRegistry {
  /// Registered completion options.
  private var completion: [Registration: CompletionRegistrationOptions] = [:]

  /// Whether dynamic registration is supported for completion.
  public var completionSupported: Bool = false

  private(set) var clientCapabilities: ClientCapabilities

  public init(clientCapabilities: ClientCapabilities) {
    self.clientCapabilities = clientCapabilities
  }

  public func registerCompletion(
    options: CompletionOptions,
    for languages: [Language]
  ) -> Registration {
    let registrationOptions = CompletionRegistrationOptions(
      documentSelector: self.documentSelector(for: languages),
      completionOptions: options)
    let registration = Registration(
        method: CompletionRequest.method,
      registerOptions: self.encode(registrationOptions))

    self.completion[registration] = registrationOptions

    return registration
  }

  /// Unregister a previously registered registration.
  public func remove(registration: Registration) {
    if registration.method == CompletionRequest.method {
      completion.removeValue(forKey: registration)
    }
  }

  public func hasCompletionRegistrations(for languages: [Language]) -> Bool {
    return self.hasAnyRegistrations(for: languages, in: self.completion)
  }

  private func documentSelector(for langauges: [Language]) -> DocumentSelector {
    return DocumentSelector(langauges.map { DocumentFilter(language: $0.rawValue) })
  }

  private func encode<T: RegistrationOptions>(_ options: T) -> LSPAny {
    var dict = [String: LSPAny]()
    options.encodeIntoLSPAny(dict: &dict)
    return .dictionary(dict)
  }

  /// Check if we have any text document registration in `registrations` scoped to
  /// one or more of the given `languages`.
  private func hasAnyRegistrations(
    for languages: [Language],
    in registrations: [Registration: TextDocumentRegistrationOptions]
  ) -> Bool {
    var languageIds: Set<String> = []
    for language in languages {
      languageIds.insert(language.rawValue)
    }

    for registration in registrations {
      guard let filters = registration.value.documentSelector else { continue }
      for filter in filters {
        guard let filterLanguage = filter.language else { continue }
        if languageIds.contains(filterLanguage) {
          return true
        }
      }
    }
    return false
  }
}
