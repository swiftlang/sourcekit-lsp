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

@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging
import SwiftExtensions

/// A class which tracks the client's capabilities as well as our dynamic
/// capability registrations in order to avoid registering conflicting
/// capabilities.
package final actor CapabilityRegistry {
  /// The client's capabilities as they were reported when sourcekit-lsp was launched.
  package nonisolated let clientCapabilities: ClientCapabilities

  // MARK: Tracking capabilities dynamically registered in the client

  /// Dynamically registered completion options.
  private var completion: [CapabilityRegistration: CompletionRegistrationOptions] = [:]

  /// Dynamically registered signature help options.
  private var signatureHelp: [CapabilityRegistration: SignatureHelpRegistrationOptions] = [:]

  /// Dynamically registered folding range options.
  private var foldingRange: [CapabilityRegistration: FoldingRangeRegistrationOptions] = [:]

  /// Dynamically registered semantic tokens options.
  private var semanticTokens: [CapabilityRegistration: SemanticTokensRegistrationOptions] = [:]

  /// Dynamically registered inlay hint options.
  private var inlayHint: [CapabilityRegistration: InlayHintRegistrationOptions] = [:]

  /// Dynamically registered pull diagnostics options.
  private var pullDiagnostics: [CapabilityRegistration: DiagnosticRegistrationOptions] = [:]

  /// Dynamically registered file watchers.
  private var didChangeWatchedFiles: (id: String, options: DidChangeWatchedFilesRegistrationOptions)?

  /// Dynamically registered command IDs.
  private var commandIds: Set<String> = []

  // MARK: Query if client has dynamic registration

  package var clientHasDynamicCompletionRegistration: Bool {
    clientCapabilities.textDocument?.completion?.dynamicRegistration == true
  }

  package var clientHasDynamicSignatureHelpRegistration: Bool {
    clientCapabilities.textDocument?.signatureHelp?.dynamicRegistration == true
  }

  package var clientHasDynamicFoldingRangeRegistration: Bool {
    clientCapabilities.textDocument?.foldingRange?.dynamicRegistration == true
  }

  package var clientHasDynamicSemanticTokensRegistration: Bool {
    clientCapabilities.textDocument?.semanticTokens?.dynamicRegistration == true
  }

  package var clientHasDynamicInlayHintRegistration: Bool {
    clientCapabilities.textDocument?.inlayHint?.dynamicRegistration == true
  }

  package var clientHasDynamicDocumentDiagnosticsRegistration: Bool {
    clientCapabilities.textDocument?.diagnostic?.dynamicRegistration == true
  }

  package var clientHasDynamicExecuteCommandRegistration: Bool {
    clientCapabilities.workspace?.executeCommand?.dynamicRegistration == true
  }

  package var clientHasDynamicDidChangeWatchedFilesRegistration: Bool {
    clientCapabilities.workspace?.didChangeWatchedFiles?.dynamicRegistration == true
  }

  // MARK: Other capability queries

  package var clientHasDiagnosticsCodeDescriptionSupport: Bool {
    clientCapabilities.textDocument?.publishDiagnostics?.codeDescriptionSupport == true
  }

  public var supportedCodeLensCommands: [SupportedCodeLensCommand: String] {
    clientCapabilities.textDocument?.codeLens?.supportedCommands ?? [:]
  }

  /// Since LSP 3.17.0, diagnostics can be reported through pull-based requests in addition to the existing push-based
  /// publish notifications.
  ///
  /// The `DiagnosticOptions` were added at the same time as the pull diagnostics request and allow specification of
  /// options for the pull diagnostics request. If the client doesn't reject this dynamic capability registration,
  /// it supports the pull diagnostics request.
  package func clientSupportsPullDiagnostics(for language: Language) -> Bool {
    registration(for: [language], in: pullDiagnostics) != nil
  }

  package nonisolated var clientSupportsActiveDocumentNotification: Bool {
    return clientHasExperimentalCapability(DidChangeActiveDocumentNotification.method)
  }

  package nonisolated var clientHasWorkspaceTestsRefreshSupport: Bool {
    return clientHasExperimentalCapability(WorkspaceTestsRefreshRequest.method)
  }

  package nonisolated var clientHasWorkspacePlaygroundsRefreshSupport: Bool {
    return clientHasExperimentalCapability(WorkspacePlaygroundsRefreshRequest.method)
  }

  package nonisolated func clientHasExperimentalCapability(_ name: String) -> Bool {
    guard case .dictionary(let experimentalCapabilities) = clientCapabilities.experimental else {
      return false
    }
    // Before Swift 6.3 we expected experimental client capabilities to be passed as `"capabilityName": true`.
    // This proved to be insufficient for experimental capabilities that evolved over time. Since 6.3 we encourage
    // clients to pass experimental capabilities as `"capabilityName": { "supported": true }`, which allows the addition
    // of more configuration parameters to the capability.
    switch experimentalCapabilities[name] {
    case .bool(true):
      return true
    case .dictionary(let dict):
      return dict["supported"] == .bool(true)
    default:
      return false
    }
  }

  // MARK: Initializer

  package init(clientCapabilities: ClientCapabilities) {
    self.clientCapabilities = clientCapabilities
  }

  // MARK: Query registered capabilities

  /// Return a registration in `registrations` for one or more of the given
  /// `languages`.
  private func registration<T: TextDocumentRegistrationOptionsProtocol>(
    for languages: [Language],
    in registrations: [CapabilityRegistration: T]
  ) -> T? {
    var languageIds: Set<String> = []
    for language in languages {
      languageIds.insert(language.rawValue)
    }

    for registration in registrations {
      let options = registration.value.textDocumentRegistrationOptions
      guard let filters = options.documentSelector else { continue }
      for filter in filters {
        guard let filterLanguage = filter.language else { continue }
        if languageIds.contains(filterLanguage) {
          return registration.value
        }
      }
    }
    return nil
  }

  // MARK: Dynamic registration of server capabilities

  /// Register a dynamic server capability with the client.
  ///
  /// If the registration of `options` for the given `method` and `languages` was successful, the capability will be
  /// added to `registrationDict` by calling `setRegistrationDict`.
  /// If registration failed, the capability won't be added to `registrationDict`.
  private func registerLanguageSpecificCapability<
    Options: RegistrationOptions & TextDocumentRegistrationOptionsProtocol & Equatable
  >(
    options: Options,
    forMethod method: String,
    languages: [Language],
    in server: SourceKitLSPServer,
    registrationDict: [CapabilityRegistration: Options],
    setRegistrationDict: (CapabilityRegistration, Options?) -> Void
  ) async {
    if let registration = registration(for: languages, in: registrationDict) {
      if options != registration {
        logger.fault(
          """
          Failed to dynamically register for \(method, privacy: .public) for \(languages, privacy: .public) \
          due to pre-existing options:
          Existing options: \(String(reflecting: registration), privacy: .public)
          New options: \(String(reflecting: options), privacy: .public)
          """
        )
      }
      return
    }

    let registration = CapabilityRegistration(
      method: method,
      registerOptions: options.encodeToLSPAny()
    )

    // Add the capability to the registration dictionary.
    // This ensures that concurrent calls for the same capability don't register it as well.
    // If the capability is rejected by the client, we remove it again.
    setRegistrationDict(registration, options)

    do {
      _ = try await server.client.send(RegisterCapabilityRequest(registrations: [registration]))
    } catch {
      setRegistrationDict(registration, nil)
    }
  }

  /// Dynamically register completion capabilities if the client supports it and
  /// we haven't yet registered any completion capabilities for the given
  /// languages.
  package func registerCompletionIfNeeded(
    options: CompletionOptions,
    for languages: [Language],
    server: SourceKitLSPServer
  ) async {
    guard clientHasDynamicCompletionRegistration else { return }

    await registerLanguageSpecificCapability(
      options: CompletionRegistrationOptions(
        documentSelector: DocumentSelector(for: languages),
        completionOptions: options
      ),
      forMethod: CompletionRequest.method,
      languages: languages,
      in: server,
      registrationDict: completion,
      setRegistrationDict: { completion[$0] = $1 }
    )
  }

  package func registerSignatureHelpIfNeeded(
    options: SignatureHelpOptions,
    for languages: [Language],
    server: SourceKitLSPServer
  ) async {
    guard clientHasDynamicCompletionRegistration else { return }

    await registerLanguageSpecificCapability(
      options: SignatureHelpRegistrationOptions(
        documentSelector: DocumentSelector(for: languages),
        signatureHelpOptions: options
      ),
      forMethod: SignatureHelpRequest.method,
      languages: languages,
      in: server,
      registrationDict: signatureHelp,
      setRegistrationDict: { signatureHelp[$0] = $1 }
    )
  }

  package func registerDidChangeWatchedFiles(
    watchers: [FileSystemWatcher],
    server: SourceKitLSPServer
  ) async {
    guard clientHasDynamicDidChangeWatchedFilesRegistration else { return }
    if let registration = didChangeWatchedFiles {
      do {
        _ = try await server.client.send(
          UnregisterCapabilityRequest(unregistrations: [
            Unregistration(id: registration.id, method: DidChangeWatchedFilesNotification.method)
          ])
        )
      } catch {
        logger.error("Failed to unregister capability \(DidChangeWatchedFilesNotification.method).")
        return
      }
    }
    let registrationOptions = DidChangeWatchedFilesRegistrationOptions(
      watchers: watchers
    )
    let registration = CapabilityRegistration(
      method: DidChangeWatchedFilesNotification.method,
      registerOptions: registrationOptions.encodeToLSPAny()
    )

    self.didChangeWatchedFiles = (registration.id, registrationOptions)

    do {
      _ = try await server.client.send(RegisterCapabilityRequest(registrations: [registration]))
    } catch {
      logger.error("Failed to dynamically register for watched files: \(error.forLogging)")
      self.didChangeWatchedFiles = nil
    }
  }

  /// Dynamically register folding range capabilities if the client supports it and
  /// we haven't yet registered any folding range capabilities for the given
  /// languages.
  package func registerFoldingRangeIfNeeded(
    options: FoldingRangeOptions,
    for languages: [Language],
    server: SourceKitLSPServer
  ) async {
    guard clientHasDynamicFoldingRangeRegistration else { return }

    await registerLanguageSpecificCapability(
      options: FoldingRangeRegistrationOptions(
        documentSelector: DocumentSelector(for: languages),
        foldingRangeOptions: options
      ),
      forMethod: FoldingRangeRequest.method,
      languages: languages,
      in: server,
      registrationDict: foldingRange,
      setRegistrationDict: { foldingRange[$0] = $1 }
    )
  }

  /// Dynamically register semantic tokens capabilities if the client supports
  /// it and we haven't yet registered any semantic tokens capabilities for the
  /// given languages.
  package func registerSemanticTokensIfNeeded(
    options: SemanticTokensOptions,
    for languages: [Language],
    server: SourceKitLSPServer
  ) async {
    guard clientHasDynamicSemanticTokensRegistration else { return }

    await registerLanguageSpecificCapability(
      options: SemanticTokensRegistrationOptions(
        documentSelector: DocumentSelector(for: languages),
        semanticTokenOptions: options
      ),
      forMethod: SemanticTokensRegistrationOptions.method,
      languages: languages,
      in: server,
      registrationDict: semanticTokens,
      setRegistrationDict: { semanticTokens[$0] = $1 }
    )
  }

  /// Dynamically register inlay hint capabilities if the client supports
  /// it and we haven't yet registered any inlay hint capabilities for the
  /// given languages.
  package func registerInlayHintIfNeeded(
    options: InlayHintOptions,
    for languages: [Language],
    server: SourceKitLSPServer
  ) async {
    guard clientHasDynamicInlayHintRegistration else { return }

    await registerLanguageSpecificCapability(
      options: InlayHintRegistrationOptions(
        documentSelector: DocumentSelector(for: languages),
        inlayHintOptions: options
      ),
      forMethod: InlayHintRequest.method,
      languages: languages,
      in: server,
      registrationDict: inlayHint,
      setRegistrationDict: { inlayHint[$0] = $1 }
    )
  }

  /// Dynamically register (pull model) diagnostic capabilities,
  /// if the client supports it.
  package func registerDiagnosticIfNeeded(
    options: DiagnosticOptions,
    for languages: [Language],
    server: SourceKitLSPServer
  ) async {
    guard clientHasDynamicDocumentDiagnosticsRegistration else { return }

    await registerLanguageSpecificCapability(
      options: DiagnosticRegistrationOptions(
        documentSelector: DocumentSelector(for: languages),
        diagnosticOptions: options
      ),
      forMethod: DocumentDiagnosticsRequest.method,
      languages: languages,
      in: server,
      registrationDict: pullDiagnostics,
      setRegistrationDict: { pullDiagnostics[$0] = $1 }
    )
  }

  /// Dynamically register executeCommand with the given IDs if the client supports
  /// it and we haven't yet registered the given command IDs yet.
  package func registerExecuteCommandIfNeeded(
    commands: [String],
    server: SourceKitLSPServer
  ) {
    guard clientHasDynamicExecuteCommandRegistration else { return }

    var newCommands = Set(commands)
    newCommands.subtract(self.commandIds)

    // We only want to send the registration with unregistered command IDs since
    // clients such as VS Code only allow a command to be registered once. We could
    // unregister all our commandIds first but this is simpler.
    guard !newCommands.isEmpty else { return }
    self.commandIds.formUnion(newCommands)

    let registration = CapabilityRegistration(
      method: ExecuteCommandRequest.method,
      registerOptions: ExecuteCommandRegistrationOptions(commands: Array(newCommands)).encodeToLSPAny()
    )

    let _ = server.client.send(RegisterCapabilityRequest(registrations: [registration])) { result in
      if let error = result.failure {
        logger.error("Failed to dynamically register commands: \(error.forLogging)")
      }
    }
  }
}

fileprivate extension DocumentSelector {
  init(for languages: [Language], scheme: String? = nil) {
    self.init(languages.map { DocumentFilter(language: $0.rawValue, scheme: scheme) })
  }
}
