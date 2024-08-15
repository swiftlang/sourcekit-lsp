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

import Foundation
import LanguageServerProtocol
import SKLogging
import SKSupport

import struct TSCBasic.AbsolutePath

/// Options that can be used to modify SourceKit-LSP's behavior.
///
/// See `ConfigurationFile.md` for a description of the configuration file's behavior.
public struct SourceKitLSPOptions: Sendable, Codable, CustomLogStringConvertible {
  public struct SwiftPMOptions: Sendable, Codable, CustomLogStringConvertible {
    /// Build configuration (debug|release).
    ///
    /// Equivalent to SwiftPM's `--configuration` option.
    public var configuration: BuildConfiguration?

    /// Build artifacts directory path. If nil, the build system may choose a default value.
    ///
    /// Equivalent to SwiftPM's `--scratch-path` option.
    public var scratchPath: String?

    /// Equivalent to SwiftPM's `--swift-sdks-path` option
    public var swiftSDKsDirectory: String?

    /// Equivalent to SwiftPM's `--swift-sdk` option
    public var swiftSDK: String?

    /// Equivalent to SwiftPM's `--triple` option
    public var triple: String?

    /// Equivalent to SwiftPM's `-Xcc` option
    public var cCompilerFlags: [String]?

    /// Equivalent to SwiftPM's `-Xcxx` option
    public var cxxCompilerFlags: [String]?

    /// Equivalent to SwiftPM's `-Xswiftc` option
    public var swiftCompilerFlags: [String]?

    /// Equivalent to SwiftPM's `-Xlinker` option
    public var linkerFlags: [String]?

    /// Equivalent to SwiftPM's `--disable-sandbox` option
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

    public var description: String {
      recursiveDescription(of: self)
    }

    public var redactedDescription: String {
      recursiveRedactedDescription(of: self)
    }
  }

  public struct CompilationDatabaseOptions: Sendable, Codable, CustomLogStringConvertible {
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

    public var description: String {
      recursiveDescription(of: self)
    }

    public var redactedDescription: String {
      recursiveRedactedDescription(of: self)
    }
  }

  public struct FallbackBuildSystemOptions: Sendable, Codable, CustomLogStringConvertible {
    public var cCompilerFlags: [String]?
    public var cxxCompilerFlags: [String]?
    public var swiftCompilerFlags: [String]?

    public init(
      cCompilerFlags: [String]? = nil,
      cxxCompilerFlags: [String]? = nil,
      swiftCompilerFlags: [String]? = nil
    ) {
      self.cCompilerFlags = cCompilerFlags
      self.cxxCompilerFlags = cxxCompilerFlags
      self.swiftCompilerFlags = swiftCompilerFlags
    }

    static func merging(
      base: FallbackBuildSystemOptions,
      override: FallbackBuildSystemOptions?
    ) -> FallbackBuildSystemOptions {
      return FallbackBuildSystemOptions(
        cCompilerFlags: override?.cCompilerFlags ?? base.cCompilerFlags,
        cxxCompilerFlags: override?.cxxCompilerFlags ?? base.cxxCompilerFlags,
        swiftCompilerFlags: override?.swiftCompilerFlags ?? base.swiftCompilerFlags
      )
    }

    public var description: String {
      recursiveDescription(of: self)
    }

    public var redactedDescription: String {
      recursiveRedactedDescription(of: self)
    }
  }

  public struct IndexOptions: Sendable, Codable, CustomLogStringConvertible {
    public var indexStorePath: String?
    public var indexDatabasePath: String?
    public var indexPrefixMap: [String: String]?
    public var maxCoresPercentageToUseForBackgroundIndexing: Double?
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

    public var description: String {
      recursiveDescription(of: self)
    }

    public var redactedDescription: String {
      recursiveRedactedDescription(of: self)
    }
  }

  public struct LoggingOptions: Sendable, Codable, CustomLogStringConvertible {
    /// The level from which one onwards log messages should be written.
    public var level: String?
    /// Whether potentially sensitive information should be redacted.
    public var privacyLevel: String?

    public init(
      level: String? = nil,
      privacyLevel: String? = nil
    ) {
      self.level = level
      self.privacyLevel = privacyLevel
    }

    static func merging(base: LoggingOptions, override: LoggingOptions?) -> LoggingOptions {
      return LoggingOptions(
        level: override?.level ?? base.level,
        privacyLevel: override?.privacyLevel ?? base.privacyLevel
      )
    }

    public var description: String {
      recursiveDescription(of: self)
    }

    public var redactedDescription: String {
      recursiveRedactedDescription(of: self)
    }
  }

  public enum BackgroundPreparationMode: String {
    /// Build a target to prepare it
    case build

    /// Prepare a target without generating object files but do not do lazy type checking.
    ///
    /// This uses SwiftPM's `--experimental-prepare-for-indexing-no-lazy` flag.
    case noLazy

    /// Prepare a target without generating object files.
    case enabled
  }

  public var swiftPM: SwiftPMOptions
  public var compilationDatabase: CompilationDatabaseOptions
  public var fallbackBuildSystem: FallbackBuildSystemOptions
  public var clangdOptions: [String]?
  public var index: IndexOptions
  public var logging: LoggingOptions

  /// Default workspace type (buildserver|compdb|swiftpm). Overrides workspace type selection logic.
  public var defaultWorkspaceType: WorkspaceType?
  public var generatedFilesPath: String?

  /// Whether background indexing is enabled.
  public var backgroundIndexing: Bool?

  public var backgroundIndexingOrDefault: Bool {
    return backgroundIndexing ?? false
  }

  public var backgroundPreparationMode: String?

  public var backgroundPreparationModeOrDefault: BackgroundPreparationMode {
    if let backgroundPreparationMode, let parsed = BackgroundPreparationMode(rawValue: backgroundPreparationMode) {
      return parsed
    }
    return .build
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
  ///
  /// This is mostly intended for testing purposes so we don't need to wait the debouncing time to get a diagnostics
  /// notification when running unit tests.
  public var swiftPublishDiagnosticsDebounceDuration: Double? = nil

  public var swiftPublishDiagnosticsDebounceDurationOrDefault: Duration {
    if let swiftPublishDiagnosticsDebounceDuration {
      return .seconds(swiftPublishDiagnosticsDebounceDuration)
    }
    return .seconds(2)
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
    swiftPM: SwiftPMOptions = .init(),
    fallbackBuildSystem: FallbackBuildSystemOptions = .init(),
    compilationDatabase: CompilationDatabaseOptions = .init(),
    clangdOptions: [String]? = nil,
    index: IndexOptions = .init(),
    logging: LoggingOptions = .init(),
    defaultWorkspaceType: WorkspaceType? = nil,
    generatedFilesPath: String? = nil,
    backgroundIndexing: Bool? = nil,
    backgroundPreparationMode: String? = nil,
    cancelTextDocumentRequestsOnEditAndClose: Bool? = nil,
    experimentalFeatures: Set<ExperimentalFeature>? = nil,
    swiftPublishDiagnosticsDebounceDuration: Double? = nil,
    workDoneProgressDebounceDuration: Double? = nil,
    sourcekitdRequestTimeout: Double? = nil
  ) {
    self.swiftPM = swiftPM
    self.fallbackBuildSystem = fallbackBuildSystem
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
      swiftPM: SwiftPMOptions.merging(base: base.swiftPM, override: override?.swiftPM),
      fallbackBuildSystem: FallbackBuildSystemOptions.merging(
        base: base.fallbackBuildSystem,
        override: override?.fallbackBuildSystem
      ),
      compilationDatabase: CompilationDatabaseOptions.merging(
        base: base.compilationDatabase,
        override: override?.compilationDatabase
      ),
      clangdOptions: override?.clangdOptions ?? base.clangdOptions,
      index: IndexOptions.merging(base: base.index, override: override?.index),
      logging: LoggingOptions.merging(base: base.logging, override: override?.logging),
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

  public var generatedFilesAbsolutePath: AbsolutePath {
    if let absolutePath = AbsolutePath(validatingOrNil: generatedFilesPath) {
      return absolutePath
    }
    return defaultDirectoryForGeneratedFiles
  }

  public func hasExperimentalFeature(_ feature: ExperimentalFeature) -> Bool {
    guard let experimentalFeatures else {
      return false
    }
    return experimentalFeatures.contains(feature)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.swiftPM = try container.decodeIfPresent(SwiftPMOptions.self, forKey: CodingKeys.swiftPM) ?? .init()
    self.compilationDatabase =
      try container.decodeIfPresent(CompilationDatabaseOptions.self, forKey: CodingKeys.compilationDatabase) ?? .init()
    self.fallbackBuildSystem =
      try container.decodeIfPresent(FallbackBuildSystemOptions.self, forKey: CodingKeys.fallbackBuildSystem) ?? .init()
    self.clangdOptions = try container.decodeIfPresent([String].self, forKey: CodingKeys.clangdOptions)
    self.index = try container.decodeIfPresent(IndexOptions.self, forKey: CodingKeys.index) ?? .init()
    self.logging = try container.decodeIfPresent(LoggingOptions.self, forKey: .logging) ?? .init()
    self.defaultWorkspaceType = try container.decodeIfPresent(
      WorkspaceType.self,
      forKey: CodingKeys.defaultWorkspaceType
    )
    self.generatedFilesPath = try container.decodeIfPresent(String.self, forKey: CodingKeys.generatedFilesPath)
    self.backgroundIndexing = try container.decodeIfPresent(Bool.self, forKey: CodingKeys.backgroundIndexing)
    self.experimentalFeatures = try container.decodeIfPresent(
      Set<ExperimentalFeature>.self,
      forKey: CodingKeys.experimentalFeatures
    )
    self.swiftPublishDiagnosticsDebounceDuration = try container.decodeIfPresent(
      Double.self,
      forKey: CodingKeys.swiftPublishDiagnosticsDebounceDuration
    )
    self.workDoneProgressDebounceDuration = try container.decodeIfPresent(
      Double.self,
      forKey: CodingKeys.workDoneProgressDebounceDuration
    )
  }

  public var description: String {
    recursiveDescription(of: self)
  }

  public var redactedDescription: String {
    recursiveRedactedDescription(of: self)
  }
}
