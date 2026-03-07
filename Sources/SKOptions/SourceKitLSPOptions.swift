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

public import Foundation
@_spi(SourceKitLSP) public import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import SKLogging

import struct TSCBasic.AbsolutePath

/// Options that can be used to modify SourceKit-LSP's behavior.
///
/// See `ConfigurationFile.md` for a description of the configuration file's behavior.
public struct SourceKitLSPOptions: Sendable, Codable, Equatable {
  public struct SwiftPMOptions: Sendable, Codable, Equatable {
    /// The configuration to build the project for during background indexing
    /// and the configuration whose build folder should be used for Swift
    /// modules if background indexing is disabled.
    ///
    /// Equivalent to SwiftPM's `--configuration` option.
    public var configuration: BuildConfiguration?

    /// Build artifacts directory path. If nil, the build system may choose a default value.
    ///
    /// This path can be specified as a relative path, which will be interpreted relative to the project root.
    /// Equivalent to SwiftPM's `--scratch-path` option.
    public var scratchPath: String?

    /// Equivalent to SwiftPM's `--swift-sdks-path` option.
    public var swiftSDKsDirectory: String?

    /// Equivalent to SwiftPM's `--swift-sdk` option.
    public var swiftSDK: String?

    /// Equivalent to SwiftPM's `--triple` option.
    public var triple: String?

    /// Equivalent to SwiftPM's `--toolset` option.
    public var toolsets: [String]?

    /// Traits to enable for the package. Equivalent to SwiftPM's `--traits` option.
    public var traits: [String]?

    /// Extra arguments passed to the compiler for C files. Equivalent to SwiftPM's `-Xcc` option.
    public var cCompilerFlags: [String]?

    /// Extra arguments passed to the compiler for C++ files. Equivalent to SwiftPM's `-Xcxx` option.
    public var cxxCompilerFlags: [String]?

    /// Extra arguments passed to the compiler for Swift files. Equivalent to SwiftPM's `-Xswiftc` option.
    public var swiftCompilerFlags: [String]?

    /// Extra arguments passed to the linker. Equivalent to SwiftPM's `-Xlinker` option.
    public var linkerFlags: [String]?

    /// Extra arguments passed to the compiler for Swift files or plugins. Equivalent to SwiftPM's
    /// `-Xbuild-tools-swiftc` option.
    public var buildToolsSwiftCompilerFlags: [String]?

    /// Disables running subprocesses from SwiftPM in a sandbox. Equivalent to SwiftPM's `--disable-sandbox` option.
    /// Useful when running `sourcekit-lsp` in a sandbox because nested sandboxes are not supported.
    public var disableSandbox: Bool?

    /// Whether to skip building and running plugins when creating the in-memory build graph.
    ///
    /// - Note: Internal option, only exists as an escape hatch in case this causes unintentional interactions with
    ///   background indexing.
    public var skipPlugins: Bool?

    /// Which SwiftPM build system should be used when opening a package.
    public var buildSystem: SwiftPMBuildSystem?

    public init(
      configuration: BuildConfiguration? = nil,
      scratchPath: String? = nil,
      swiftSDKsDirectory: String? = nil,
      swiftSDK: String? = nil,
      triple: String? = nil,
      toolsets: [String]? = nil,
      traits: [String]? = nil,
      cCompilerFlags: [String]? = nil,
      cxxCompilerFlags: [String]? = nil,
      swiftCompilerFlags: [String]? = nil,
      linkerFlags: [String]? = nil,
      buildToolsSwiftCompilerFlags: [String]? = nil,
      disableSandbox: Bool? = nil,
      skipPlugins: Bool? = nil,
      buildSystem: SwiftPMBuildSystem? = nil
    ) {
      self.configuration = configuration
      self.scratchPath = scratchPath
      self.swiftSDKsDirectory = swiftSDKsDirectory
      self.swiftSDK = swiftSDK
      self.triple = triple
      self.toolsets = toolsets
      self.traits = traits
      self.cCompilerFlags = cCompilerFlags
      self.cxxCompilerFlags = cxxCompilerFlags
      self.swiftCompilerFlags = swiftCompilerFlags
      self.linkerFlags = linkerFlags
      self.buildToolsSwiftCompilerFlags = buildToolsSwiftCompilerFlags
      self.disableSandbox = disableSandbox
      self.buildSystem = buildSystem
    }

    static func merging(base: SwiftPMOptions, override: SwiftPMOptions?) -> SwiftPMOptions {
      return SwiftPMOptions(
        configuration: override?.configuration ?? base.configuration,
        scratchPath: override?.scratchPath ?? base.scratchPath,
        swiftSDKsDirectory: override?.swiftSDKsDirectory ?? base.swiftSDKsDirectory,
        swiftSDK: override?.swiftSDK ?? base.swiftSDK,
        triple: override?.triple ?? base.triple,
        toolsets: override?.toolsets ?? base.toolsets,
        traits: override?.traits ?? base.traits,
        cCompilerFlags: override?.cCompilerFlags ?? base.cCompilerFlags,
        cxxCompilerFlags: override?.cxxCompilerFlags ?? base.cxxCompilerFlags,
        swiftCompilerFlags: override?.swiftCompilerFlags ?? base.swiftCompilerFlags,
        linkerFlags: override?.linkerFlags ?? base.linkerFlags,
        buildToolsSwiftCompilerFlags: override?.buildToolsSwiftCompilerFlags ?? base.buildToolsSwiftCompilerFlags,
        disableSandbox: override?.disableSandbox ?? base.disableSandbox,
        skipPlugins: override?.skipPlugins ?? base.skipPlugins,
        buildSystem: override?.buildSystem ?? base.buildSystem
      )
    }
  }

  public struct CompilationDatabaseOptions: Sendable, Codable, Equatable {
    /// Additional paths to search for a compilation database, relative to a workspace root.
    public var searchPaths: [String]?

    public init(searchPaths: [String]? = nil) {
      self.searchPaths = searchPaths
    }

    static func merging(
      base: CompilationDatabaseOptions,
      override: CompilationDatabaseOptions?
    ) -> CompilationDatabaseOptions {
      return CompilationDatabaseOptions(searchPaths: override?.searchPaths ?? base.searchPaths)
    }
  }

  public struct FallbackBuildSystemOptions: Sendable, Codable, Equatable {
    /// Extra arguments passed to the compiler for C files.
    public var cCompilerFlags: [String]?
    /// Extra arguments passed to the compiler for C++ files.
    public var cxxCompilerFlags: [String]?
    /// Extra arguments passed to the compiler for Swift files.
    public var swiftCompilerFlags: [String]?
    /// The SDK to use for fallback arguments. Default is to infer the SDK using `xcrun`.
    public var sdk: String?

    public init(
      cCompilerFlags: [String]? = nil,
      cxxCompilerFlags: [String]? = nil,
      swiftCompilerFlags: [String]? = nil,
      sdk: String? = nil
    ) {
      self.cCompilerFlags = cCompilerFlags
      self.cxxCompilerFlags = cxxCompilerFlags
      self.swiftCompilerFlags = swiftCompilerFlags
      self.sdk = sdk
    }

    static func merging(
      base: FallbackBuildSystemOptions,
      override: FallbackBuildSystemOptions?
    ) -> FallbackBuildSystemOptions {
      return FallbackBuildSystemOptions(
        cCompilerFlags: override?.cCompilerFlags ?? base.cCompilerFlags,
        cxxCompilerFlags: override?.cxxCompilerFlags ?? base.cxxCompilerFlags,
        swiftCompilerFlags: override?.swiftCompilerFlags ?? base.swiftCompilerFlags,
        sdk: override?.sdk ?? base.sdk
      )
    }
  }

  public struct IndexOptions: Sendable, Codable, Equatable {
    /// Path remappings for remapping index data for local use.
    public var indexPrefixMap: [String: String]?
    /// A hint indicating how many cores background indexing should use at most (value between 0 and 1). Background indexing is not required to honor this setting.
    ///
    /// - Note: Internal option, may not work as intended
    public var maxCoresPercentageToUseForBackgroundIndexing: Double?
    /// Number of seconds to wait for an update index store task to finish before terminating it.
    public var updateIndexStoreTimeout: Int?

    public var maxCoresPercentageToUseForBackgroundIndexingOrDefault: Double {
      return maxCoresPercentageToUseForBackgroundIndexing ?? 1
    }

    public var updateIndexStoreTimeoutOrDefault: Duration {
      if let updateIndexStoreTimeout {
        .seconds(updateIndexStoreTimeout)
      } else {
        .seconds(120)
      }
    }

    public init(
      indexPrefixMap: [String: String]? = nil,
      maxCoresPercentageToUseForBackgroundIndexing: Double? = nil,
      updateIndexStoreTimeout: Int? = nil
    ) {
      self.indexPrefixMap = indexPrefixMap
      self.maxCoresPercentageToUseForBackgroundIndexing = maxCoresPercentageToUseForBackgroundIndexing
      self.updateIndexStoreTimeout = updateIndexStoreTimeout
    }

    static func merging(base: IndexOptions, override: IndexOptions?) -> IndexOptions {
      return IndexOptions(
        indexPrefixMap: override?.indexPrefixMap ?? base.indexPrefixMap,
        maxCoresPercentageToUseForBackgroundIndexing: override?.maxCoresPercentageToUseForBackgroundIndexing
          ?? base.maxCoresPercentageToUseForBackgroundIndexing,
        updateIndexStoreTimeout: override?.updateIndexStoreTimeout ?? base.updateIndexStoreTimeout
      )
    }
  }

  public struct LoggingOptions: Sendable, Codable, Equatable {
    /// The level from which one onwards log messages should be written.
    public var level: String?

    /// Whether potentially sensitive information should be redacted.
    /// Default is `public`, which redacts potentially sensitive information.
    public var privacyLevel: String?

    /// Write all input received by SourceKit-LSP on stdin to a file in this directory.
    ///
    /// Useful to record and replay an entire SourceKit-LSP session.
    public var inputMirrorDirectory: String?

    /// Write all data sent from SourceKit-LSP to the client to a file in this directory.
    ///
    /// Useful to record the raw communication between SourceKit-LSP and the client on a low level.
    public var outputMirrorDirectory: String?

    public init(
      level: String? = nil,
      privacyLevel: String? = nil,
      inputMirrorDirectory: String? = nil,
      outputMirrorDirectory: String? = nil
    ) {
      self.level = level
      self.privacyLevel = privacyLevel
      self.inputMirrorDirectory = inputMirrorDirectory
      self.outputMirrorDirectory = outputMirrorDirectory
    }

    static func merging(base: LoggingOptions, override: LoggingOptions?) -> LoggingOptions {
      return LoggingOptions(
        level: override?.level ?? base.level,
        privacyLevel: override?.privacyLevel ?? base.privacyLevel,
        inputMirrorDirectory: override?.inputMirrorDirectory ?? base.inputMirrorDirectory,
        outputMirrorDirectory: override?.outputMirrorDirectory ?? base.outputMirrorDirectory
      )
    }
  }

  public struct SourceKitDOptions: Sendable, Codable, Equatable {
    /// When set, load the SourceKit client plugin from this path instead of locating it inside the toolchain.
    ///
    /// - Note: Internal option, only to be used while running SourceKit-LSP tests
    public var clientPlugin: String?

    /// When set, load the SourceKit service plugin from this path instead of locating it inside the toolchain.
    ///
    /// - Note: Internal option, only to be used while running SourceKit-LSP tests
    public var servicePlugin: String?

    public init(clientPlugin: String? = nil, servicePlugin: String? = nil) {
      self.clientPlugin = clientPlugin
      self.servicePlugin = servicePlugin
    }

    static func merging(base: SourceKitDOptions, override: SourceKitDOptions?) -> SourceKitDOptions {
      return SourceKitDOptions(
        clientPlugin: override?.clientPlugin ?? base.clientPlugin,
        servicePlugin: override?.servicePlugin ?? base.servicePlugin
      )
    }
  }

  public enum BackgroundPreparationMode: String, Sendable, Codable, Equatable {
    /// Build a target to prepare it.
    case build

    /// Prepare a target without generating object files but do not do lazy type checking and function body skipping.
    ///
    /// This uses SwiftPM's `--experimental-prepare-for-indexing-no-lazy` flag.
    case noLazy

    /// Prepare a target without generating object files.
    case enabled
  }

  /// Options for SwiftPM workspaces.
  private var swiftPM: SwiftPMOptions?
  public var swiftPMOrDefault: SwiftPMOptions {
    get { swiftPM ?? .init() }
    set { swiftPM = newValue }
  }

  /// Dictionary with the following keys, defining options for workspaces with a compilation database.
  private var compilationDatabase: CompilationDatabaseOptions?
  public var compilationDatabaseOrDefault: CompilationDatabaseOptions {
    get { compilationDatabase ?? .init() }
    set { compilationDatabase = newValue }
  }

  /// Dictionary with the following keys, defining options for files that aren't managed by any build server.
  private var fallbackBuildSystem: FallbackBuildSystemOptions?
  public var fallbackBuildSystemOrDefault: FallbackBuildSystemOptions {
    get { fallbackBuildSystem ?? .init() }
    set { fallbackBuildSystem = newValue }
  }

  /// Number of milliseconds to wait for build settings from the build server before using fallback build settings.
  public var buildSettingsTimeout: Int?
  public var buildSettingsTimeoutOrDefault: Duration {
    // The default timeout of 500ms was chosen arbitrarily without any measurements.
    .milliseconds(buildSettingsTimeout ?? 500)
  }

  /// Extra command line arguments passed to `clangd` when launching it.
  public var clangdOptions: [String]?

  /// Options related to indexing.
  private var index: IndexOptions?
  public var indexOrDefault: IndexOptions {
    get { index ?? .init() }
    set { index = newValue }
  }

  /// Options related to logging, changing SourceKit-LSP’s logging behavior on non-Apple platforms.
  ///
  /// On Apple platforms, logging is done through the [system log](Diagnose%20Bundle.md#Enable%20Extended%20Logging).
  /// These options can only be set globally and not per workspace.
  private var logging: LoggingOptions?
  public var loggingOrDefault: LoggingOptions {
    get { logging ?? .init() }
    set { logging = newValue }
  }

  /// Options modifying the behavior of sourcekitd.
  private var sourcekitd: SourceKitDOptions?
  public var sourcekitdOrDefault: SourceKitDOptions {
    get { sourcekitd ?? .init() }
    set { sourcekitd = newValue }
  }

  /// Default workspace type. Overrides workspace type selection logic.
  public var defaultWorkspaceType: WorkspaceType?
  /// Directory in which generated interfaces and macro expansions should be stored.
  public var generatedFilesPath: String?

  /// Whether background indexing is enabled.
  public var backgroundIndexing: Bool?

  public var backgroundIndexingOrDefault: Bool {
    return backgroundIndexing ?? true
  }

  /// Determines how background indexing should prepare a target.
  public var backgroundPreparationMode: BackgroundPreparationMode?

  public var backgroundPreparationModeOrDefault: BackgroundPreparationMode {
    return backgroundPreparationMode ?? .enabled
  }

  /// Whether sending a `textDocument/didChange` or `textDocument/didClose` notification for a document should cancel
  /// all pending requests for that document.
  public var cancelTextDocumentRequestsOnEditAndClose: Bool? = nil

  public var cancelTextDocumentRequestsOnEditAndCloseOrDefault: Bool {
    return cancelTextDocumentRequestsOnEditAndClose ?? true
  }

  /// Whether the response for `textDocument/semanticTokens` should include semantic tokens for syntactic and semantic
  /// highlighting or just semantic highlighting. This should be enabled in cases where the syntactic grammar
  /// (e.g. TextMate or tree-sitter) used by an editor is insufficient for properly highlighting the source code. This
  /// can happen for example happen when using complex string interpolations or nested raw strings.
  public var reportSyntacticHighlightInSemanticTokens: Bool? = nil

  public var reportSyntacticHighlightInSemanticTokensOrDefault: Bool {
    return reportSyntacticHighlightInSemanticTokens ?? false
  }

  /// Experimental features that are enabled.
  public var experimentalFeatures: Set<ExperimentalFeature>? = nil

  /// The time that `SwiftLanguageService` should wait after an edit before starting to compute diagnostics and
  /// sending a `PublishDiagnosticsNotification`.
  public var swiftPublishDiagnosticsDebounceDuration: Double? = nil

  public var swiftPublishDiagnosticsDebounceDurationOrDefault: Duration {
    if let swiftPublishDiagnosticsDebounceDuration {
      return .seconds(swiftPublishDiagnosticsDebounceDuration)
    }
    return .seconds(1)
  }

  /// When a task is started that should be displayed to the client as a work done progress, how many milliseconds to
  /// wait before actually starting the work done progress. This prevents flickering of the work done progress in the
  /// client for short-lived index tasks which end within this duration.
  public var workDoneProgressDebounceDuration: Double? = nil

  public var workDoneProgressDebounceDurationOrDefault: Duration {
    if let workDoneProgressDebounceDuration {
      return .seconds(workDoneProgressDebounceDuration)
    }
    return .seconds(1)
  }

  /// The maximum duration that a sourcekitd request should be allowed to execute before being declared as timed out.
  ///
  /// In general, editors should cancel requests that they are no longer interested in, but in case editors don't cancel
  /// requests, this ensures that a long-running non-cancelled request is not blocking sourcekitd and thus most semantic
  /// functionality.
  ///
  /// In particular, VS Code does not cancel the semantic tokens request, which can cause a long-running AST build that
  /// blocks sourcekitd.
  public var sourcekitdRequestTimeout: Double? = nil

  public var sourcekitdRequestTimeoutOrDefault: Duration {
    if let sourcekitdRequestTimeout {
      return .seconds(sourcekitdRequestTimeout)
    }
    return .seconds(120)
  }

  /// If a request to sourcekitd or clangd exceeds this timeout, we assume that the semantic service provider is hanging
  /// for some reason and won't recover. To restore semantic functionality, we terminate and restart it.
  public var semanticServiceRestartTimeout: Double? = nil

  public var semanticServiceRestartTimeoutOrDefault: Duration {
    if let semanticServiceRestartTimeout {
      return .seconds(semanticServiceRestartTimeout)
    }
    return .seconds(300)
  }

  /// Duration how long to wait for responses to `workspace/buildTargets` or `buildTarget/sources` request by the build
  /// server before defaulting to an empty response.
  public var buildServerWorkspaceRequestsTimeout: Double? = nil

  public var buildServerWorkspaceRequestsTimeoutOrDefault: Duration {
    if let buildServerWorkspaceRequestsTimeout {
      return .seconds(buildServerWorkspaceRequestsTimeout)
    }
    // The default value needs to strike a balance: If the build server is slow to respond, we don't want to constantly
    // run into this timeout, which causes somewhat expensive computations because we trigger the `buildTargetsChanged`
    // chain.
    // At the same time, we do want to provide functionality based on fallback settings after some time.
    // 15s seems like it should strike a balance here but there is no data backing this value up.
    return .seconds(15)
  }

  /// Defines the batch size for target preparation.
  /// If nil, defaults to preparing 1 target at a time.
  public var preparationBatchingStrategy: PreparationBatchingStrategy?

  public init(
    swiftPM: SwiftPMOptions? = .init(),
    fallbackBuildSystem: FallbackBuildSystemOptions? = .init(),
    buildSettingsTimeout: Int? = nil,
    compilationDatabase: CompilationDatabaseOptions? = .init(),
    clangdOptions: [String]? = nil,
    index: IndexOptions? = .init(),
    logging: LoggingOptions? = .init(),
    sourcekitd: SourceKitDOptions? = .init(),
    defaultWorkspaceType: WorkspaceType? = nil,
    generatedFilesPath: String? = nil,
    backgroundIndexing: Bool? = nil,
    backgroundPreparationMode: BackgroundPreparationMode? = nil,
    preparationBatchingStrategy: PreparationBatchingStrategy? = nil,
    cancelTextDocumentRequestsOnEditAndClose: Bool? = nil,
    reportSyntacticHighlightInSemanticTokens: Bool? = nil,
    experimentalFeatures: Set<ExperimentalFeature>? = nil,
    swiftPublishDiagnosticsDebounceDuration: Double? = nil,
    workDoneProgressDebounceDuration: Double? = nil,
    sourcekitdRequestTimeout: Double? = nil,
    semanticServiceRestartTimeout: Double? = nil,
    buildServerWorkspaceRequestsTimeout: Double? = nil
  ) {
    self.swiftPM = swiftPM
    self.fallbackBuildSystem = fallbackBuildSystem
    self.buildSettingsTimeout = buildSettingsTimeout
    self.compilationDatabase = compilationDatabase
    self.clangdOptions = clangdOptions
    self.index = index
    self.logging = logging
    self.sourcekitd = sourcekitd
    self.generatedFilesPath = generatedFilesPath
    self.defaultWorkspaceType = defaultWorkspaceType
    self.backgroundIndexing = backgroundIndexing
    self.backgroundPreparationMode = backgroundPreparationMode
    self.preparationBatchingStrategy = preparationBatchingStrategy
    self.cancelTextDocumentRequestsOnEditAndClose = cancelTextDocumentRequestsOnEditAndClose
    self.reportSyntacticHighlightInSemanticTokens = reportSyntacticHighlightInSemanticTokens
    self.experimentalFeatures = experimentalFeatures
    self.swiftPublishDiagnosticsDebounceDuration = swiftPublishDiagnosticsDebounceDuration
    self.workDoneProgressDebounceDuration = workDoneProgressDebounceDuration
    self.sourcekitdRequestTimeout = sourcekitdRequestTimeout
    self.semanticServiceRestartTimeout = semanticServiceRestartTimeout
    self.buildServerWorkspaceRequestsTimeout = buildServerWorkspaceRequestsTimeout
  }

  public init?(fromLSPAny lspAny: LSPAny?) throws {
    guard let lspAny else {
      return nil
    }
    let jsonEncoded = try JSONEncoder().encode(lspAny)
    self = try JSONDecoder().decode(Self.self, from: jsonEncoded)
  }

  public var asLSPAny: LSPAny {
    get throws {
      let jsonEncoded = try JSONEncoder().encode(self)
      return try JSONDecoder().decode(LSPAny.self, from: jsonEncoded)
    }
  }

  public init?(path: URL?) {
    guard let path, let contents = try? Data(contentsOf: path) else {
      return nil
    }
    guard
      let decoded = orLog(
        "Parsing config.json",
        { try JSONDecoder().decode(Self.self, from: contents) }
      )
    else {
      return nil
    }

    logger.log("Read options from \(path)")
    logger.logFullObjectInMultipleLogMessages(header: "Config file options", loggingProxy)

    self = decoded
  }

  public static func merging(base: SourceKitLSPOptions, override: SourceKitLSPOptions?) -> SourceKitLSPOptions {
    return SourceKitLSPOptions(
      swiftPM: SwiftPMOptions.merging(base: base.swiftPMOrDefault, override: override?.swiftPM),
      fallbackBuildSystem: FallbackBuildSystemOptions.merging(
        base: base.fallbackBuildSystemOrDefault,
        override: override?.fallbackBuildSystem
      ),
      buildSettingsTimeout: override?.buildSettingsTimeout ?? base.buildSettingsTimeout,
      compilationDatabase: CompilationDatabaseOptions.merging(
        base: base.compilationDatabaseOrDefault,
        override: override?.compilationDatabase
      ),
      clangdOptions: override?.clangdOptions ?? base.clangdOptions,
      index: IndexOptions.merging(base: base.indexOrDefault, override: override?.index),
      logging: LoggingOptions.merging(base: base.loggingOrDefault, override: override?.logging),
      sourcekitd: SourceKitDOptions.merging(base: base.sourcekitdOrDefault, override: override?.sourcekitd),
      defaultWorkspaceType: override?.defaultWorkspaceType ?? base.defaultWorkspaceType,
      generatedFilesPath: override?.generatedFilesPath ?? base.generatedFilesPath,
      backgroundIndexing: override?.backgroundIndexing ?? base.backgroundIndexing,
      backgroundPreparationMode: override?.backgroundPreparationMode ?? base.backgroundPreparationMode,
      preparationBatchingStrategy: override?.preparationBatchingStrategy ?? base.preparationBatchingStrategy,
      cancelTextDocumentRequestsOnEditAndClose: override?.cancelTextDocumentRequestsOnEditAndClose
        ?? base.cancelTextDocumentRequestsOnEditAndClose,
      reportSyntacticHighlightInSemanticTokens: override?.reportSyntacticHighlightInSemanticTokens
        ?? base.reportSyntacticHighlightInSemanticTokens,
      experimentalFeatures: override?.experimentalFeatures ?? base.experimentalFeatures,
      swiftPublishDiagnosticsDebounceDuration: override?.swiftPublishDiagnosticsDebounceDuration
        ?? base.swiftPublishDiagnosticsDebounceDuration,
      workDoneProgressDebounceDuration: override?.workDoneProgressDebounceDuration
        ?? base.workDoneProgressDebounceDuration,
      sourcekitdRequestTimeout: override?.sourcekitdRequestTimeout ?? base.sourcekitdRequestTimeout,
      semanticServiceRestartTimeout: override?.semanticServiceRestartTimeout ?? base.semanticServiceRestartTimeout,
      buildServerWorkspaceRequestsTimeout: override?.buildServerWorkspaceRequestsTimeout
        ?? base.buildServerWorkspaceRequestsTimeout
    )
  }

  package static func merging(base: SourceKitLSPOptions, workspaceFolder: DocumentURI) -> SourceKitLSPOptions {
    return SourceKitLSPOptions.merging(
      base: base,
      override: SourceKitLSPOptions(
        path: workspaceFolder.fileURL?
          .appending(components: ".sourcekit-lsp", "config.json")
      )
    )
  }

  public var generatedFilesAbsolutePath: URL {
    if let generatedFilesPath {
      return URL(fileURLWithPath: generatedFilesPath)
    }

    return URL(fileURLWithPath: NSTemporaryDirectory()).appending(component: "sourcekit-lsp")
  }

  public func hasExperimentalFeature(_ feature: ExperimentalFeature) -> Bool {
    guard let experimentalFeatures else {
      return false
    }
    return experimentalFeatures.contains(feature)
  }
}

extension SourceKitLSPOptions {
  /// Options proxy to avoid public import of `SKLogging`.
  ///
  /// We can't conform `SourceKitLSPOptions` to `CustomLogStringConvertible` because that would require a public import
  /// of `SKLogging`. Instead, define a package type that performs the logging of `SourceKitLSPOptions`.
  package struct LoggingProxy: CustomLogStringConvertible {
    let options: SourceKitLSPOptions

    package var description: String {
      options.prettyPrintedJSON
    }

    package var redactedDescription: String {
      options.prettyPrintedRedactedJSON
    }
  }

  package var loggingProxy: LoggingProxy {
    LoggingProxy(options: self)
  }
}
