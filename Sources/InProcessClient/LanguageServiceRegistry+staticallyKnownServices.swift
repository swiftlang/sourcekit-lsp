import LanguageServerProtocol
package import SourceKitLSP

extension LanguageServiceRegistry {
  /// All types conforming to `LanguageService` that are known at compile time.
  package static let staticallyKnownServices = {
    var registry = LanguageServiceRegistry()
    registry.register(ClangLanguageService.self, for: [.c, .cpp, .objective_c, .objective_cpp])
    registry.register(SwiftLanguageService.self, for: [.swift])
    registry.register(DocumentationLanguageService.self, for: [.markdown, .tutorial])
    return registry
  }()
}
