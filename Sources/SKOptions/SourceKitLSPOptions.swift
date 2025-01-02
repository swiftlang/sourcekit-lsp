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

#if compiler(>=6)
public import Foundation
public import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging

import struct TSCBasic.AbsolutePath
#else
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolExtensions
import SKLogging

import struct TSCBasic.AbsolutePath
#endif

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

    /// Extra arguments passed to the compiler for C files. Equivalent to SwiftPM's `-Xcc` option.
    public var cCompilerFlags: [String]?

    /// Extra arguments passed to the compiler for C++ files. Equivalent to SwiftPM's `-Xcxx` option.
    public var cxxCompilerFlags: [String]?

    /// Extra arguments passed to the compiler for Swift files. Equivalent to SwiftPM's `-Xswiftc` option.
    public var swiftCompilerFlags: [String]?

    /// Extra arguments passed to the linker. Equivalent to SwiftPM's `-Xlinker` option.
    public var linkerFlags: [String]?

    /// Disables running subprocesses from SwiftPM in a sandbox. Equivalent to SwiftPM's `--disable-sandbox` option.
    /// Useful when running `sourcekit-lsp` in a sandbox because nested sandboxes are not supported.
    public var disableSandbox: Bool?

    public init(
      configuration: BuildConfiguration? = nil,
      scratchPath: String? = nil,
      swiftSDKsDirectory: String? = nil,
      swiftSDK: String? = nil,
      triple: String? = nil,
      cCompilerFlags: [String]? = nil,
      cxxCompilerFlags: [String]? = nil,
      swiftCompilerFlags: [String]? = nil,
      linkerFlags: [String]? = nil,
      disableSandbox: Bool? = nil
    ) {
      self.configuration = configuration
      self.scratchPath = scratchPath
      self.swiftSDKsDirectory = swiftSDKsDirectory
      self.swiftSDK = swiftSDK
      self.triple = triple
      self.cCompilerFlags = cCompilerFlags
      self.cxxCompilerFlags = cxxCompilerFlags
      self.swiftCompilerFlags = swiftCompilerFlags
      self.linkerFlags = linkerFlags
      self.disableSandbox = disableSandbox
    }

    static func merging(base: SwiftPMOptions, override: SwiftPMOptions?) -> SwiftPMOptions {
      return SwiftPMOptions(
        configuration: override?.configuration ?? base.configuration,
        scratchPath: override?.scratchPath ?? base.scratchPath,
        swiftSDKsDirectory: override?.swiftSDKsDirectory ?? base.swiftSDKsDirectory,
        swiftSDK: override?.swiftSDK ?? base.swiftSDK,
        triple: override?.triple ?? base.triple,
        cCompilerFlags: override?.cCompilerFlags ?? base.cCompilerFlags,
        cxxCompilerFlags: override?.cxxCompilerFlags ?? base.cxxCompilerFlags,
        swiftCompilerFlags: override?.swiftCompilerFlags ?? base.swiftCompilerFlags,
        linkerFlags: override?.linkerFlags ?? base.linkerFlags,
        disableSandbox: override?.disableSandbox ?? base.disableSandbox
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
    /// Directory in which a separate compilation stores the index store. By default, inferred from the build system.
    public var indexStorePath: String?
    /// Directory in which the indexstore-db should be stored. By default, inferred from the build system.
    public var indexDatabasePath: String?
    /// Path remappings for remapping index data for local use.
    public var indexPrefixMap: [String: String]?
    /// A hint indicating how many cores background indexing should use at most (value between 0 and 1). Background indexing is not required to honor this setting.
    public var maxCoresPercentageToUseForBackgroundIndexing: Double?
    /// Number of seconds to wait for an update index store task to finish before killing it.
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
      indexStorePath: String? = nil,
      indexDatabasePath: String? = nil,
      indexPrefixMap: [String: String]? = nil,
      maxCoresPercentageToUseForBackgroundIndexing: Double? = nil,
      updateIndexStoreTimeout: Int? = nil
    ) {
      self.indexStorePath = indexStorePath
      self.indexDatabasePath = indexDatabasePath
      self.indexPrefixMap = indexPrefixMap
      self.maxCoresPercentageToUseForBackgroundIndexing = maxCoresPercentageToUseForBackgroundIndexing
      self.updateIndexStoreTimeout = updateIndexStoreTimeout
    }

    static func merging(base: IndexOptions, override: IndexOptions?) -> IndexOptions {
      return IndexOptions(
        indexStorePath: override?.indexStorePath ?? base.indexStorePath,
        indexDatabasePath: override?.indexDatabasePath ?? base.indexDatabasePath,
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

    public init(
      level: String? = nil,
      privacyLevel: String? = nil,
      inputMirrorDirectory: String? = nil
    ) {
      self.level = level
      self.privacyLevel = privacyLevel
      self.inputMirrorDirectory = inputMirrorDirectory
    }

    static func merging(base: LoggingOptions, override: LoggingOptions?) -> LoggingOptions {
      return LoggingOptions(
        level: override?.level ?? base.level,
        privacyLevel: override?.privacyLevel ?? base.privacyLevel,
        inputMirrorDirectory: override?.inputMirrorDirectory ?? base.inputMirrorDirectory
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

  /// Dictionary with the following keys, defining options for files that aren't managed by any build system.
  private var fallbackBuildSystem: FallbackBuildSystemOptions?
  public var fallbackBuildSystemOrDefault: FallbackBuildSystemOptions {
    get { fallbackBuildSystem ?? .init() }
    set { fallbackBuildSystem = newValue }
  }

  /// Number of milliseconds to wait for build settings from the build system before using fallback build settings.
  public var buildSettingsTimeout: Int?
  public var buildSettingsTimeoutOrDefault: Duration {
    // The default timeout of 500ms was chosen arbitrarily without any measurements.
    get { .milliseconds(buildSettingsTimeout ?? 500) }
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

  public init(
    swiftPM: SwiftPMOptions? = .init(),
    fallbackBuildSystem: FallbackBuildSystemOptions? = .init(),
    buildSettingsTimeout: Int? = nil,
    compilationDatabase: CompilationDatabaseOptions? = .init(),
    clangdOptions: [String]? = nil,
    index: IndexOptions? = .init(),
    logging: LoggingOptions? = .init(),
    defaultWorkspaceType: WorkspaceType? = nil,
    generatedFilesPath: String? = nil,
    backgroundIndexing: Bool? = nil,
    backgroundPreparationMode: BackgroundPreparationMode? = nil,
    cancelTextDocumentRequestsOnEditAndClose: Bool? = nil,
    experimentalFeatures: Set<ExperimentalFeature>? = nil,
    swiftPublishDiagnosticsDebounceDuration: Double? = nil,
    workDoneProgressDebounceDuration: Double? = nil,
    sourcekitdRequestTimeout: Double? = nil
  ) {
    self.swiftPM = swiftPM
    self.fallbackBuildSystem = fallbackBuildSystem
    self.buildSettingsTimeout = buildSettingsTimeout
    self.compilationDatabase = compilationDatabase
    self.clangdOptions = clangdOptions
    self.index = index
    self.logging = logging
    self.generatedFilesPath = generatedFilesPath
    self.defaultWorkspaceType = defaultWorkspaceType
    self.backgroundIndexing = backgroundIndexing
    self.backgroundPreparationMode = backgroundPreparationMode
    self.cancelTextDocumentRequestsOnEditAndClose = cancelTextDocumentRequestsOnEditAndClose
    self.experimentalFeatures = experimentalFeatures
    self.swiftPublishDiagnosticsDebounceDuration = swiftPublishDiagnosticsDebounceDuration
    self.workDoneProgressDebounceDuration = workDoneProgressDebounceDuration
    self.sourcekitdRequestTimeout = sourcekitdRequestTimeout
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
    self = decoded
  }

  public static func merging(base: SourceKitLSPOptions, override: SourceKitLSPOptions?) -> SourceKitLSPOptions {
    return SourceKitLSPOptions(
      swiftPM: SwiftPMOptions.merging(base: base.swiftPMOrDefault, override: override?.swiftPM),
      fallbackBuildSystem: FallbackBuildSystemOptions.merging(
        base: base.fallbackBuildSystemOrDefault,
        override: override?.fallbackBuildSystem
      ),
      buildSettingsTimeout: override?.buildSettingsTimeout,
      compilationDatabase: CompilationDatabaseOptions.merging(
        base: base.compilationDatabaseOrDefault,
        override: override?.compilationDatabase
      ),
      clangdOptions: override?.clangdOptions ?? base.clangdOptions,
      index: IndexOptions.merging(base: base.indexOrDefault, override: override?.index),
      logging: LoggingOptions.merging(base: base.loggingOrDefault, override: override?.logging),
      defaultWorkspaceType: override?.defaultWorkspaceType ?? base.defaultWorkspaceType,
      generatedFilesPath: override?.generatedFilesPath ?? base.generatedFilesPath,
      backgroundIndexing: override?.backgroundIndexing ?? base.backgroundIndexing,
      backgroundPreparationMode: override?.backgroundPreparationMode ?? base.backgroundPreparationMode,
      cancelTextDocumentRequestsOnEditAndClose: override?.cancelTextDocumentRequestsOnEditAndClose
        ?? base.cancelTextDocumentRequestsOnEditAndClose,
      experimentalFeatures: override?.experimentalFeatures ?? base.experimentalFeatures,
      swiftPublishDiagnosticsDebounceDuration: override?.swiftPublishDiagnosticsDebounceDuration
        ?? base.swiftPublishDiagnosticsDebounceDuration,
      workDoneProgressDebounceDuration: override?.workDoneProgressDebounceDuration
        ?? base.workDoneProgressDebounceDuration,
      sourcekitdRequestTimeout: override?.sourcekitdRequestTimeout ?? base.sourcekitdRequestTimeout
    )
  }

  public var generatedFilesAbsolutePath: URL {
    if let generatedFilesPath {
      return URL(fileURLWithPath: generatedFilesPath)
    }

    return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sourcekit-lsp")
  }

  public func hasExperimentalFeature(_ feature: ExperimentalFeature) -> Bool {
    guard let experimentalFeatures else {
      return false
    }
    return experimentalFeatures.contains(feature)
  }
}
