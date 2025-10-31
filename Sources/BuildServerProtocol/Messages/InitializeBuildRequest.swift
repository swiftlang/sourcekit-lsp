//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public import LanguageServerProtocol

/// Like the language server protocol, the initialize request is sent
/// as the first request from the client to the server. If the server
/// receives a request or notification before the initialize request
/// it should act as follows:
///
/// - For a request the response should be an error with code: -32002.
///   The message can be picked by the server.
///
/// - Notifications should be dropped, except for the exit notification.
///   This will allow the exit of a server without an initialize request.
///
/// Until the server has responded to the initialize request with an
/// InitializeBuildResult, the client must not send any additional
/// requests or notifications to the server.
public struct InitializeBuildRequest: BSPRequest, Hashable {
  public static let method: String = "build/initialize"
  public typealias Response = InitializeBuildResponse

  /// Name of the client
  public var displayName: String

  /// The version of the client
  public var version: String

  /// The BSP version that the client speaks=
  public var bspVersion: String

  /// The rootUri of the workspace
  public var rootUri: URI

  /// The capabilities of the client
  public var capabilities: BuildClientCapabilities

  /// Kind of data to expect in the `data` field. If this field is not set, the kind of data is not specified. */
  public var dataKind: InitializeBuildRequestDataKind?

  /// Additional metadata about the client
  public var data: LSPAny?

  public init(
    displayName: String,
    version: String,
    bspVersion: String,
    rootUri: URI,
    capabilities: BuildClientCapabilities,
    dataKind: InitializeBuildRequestDataKind? = nil,
    data: LSPAny? = nil
  ) {
    self.displayName = displayName
    self.version = version
    self.bspVersion = bspVersion
    self.rootUri = rootUri
    self.capabilities = capabilities
    self.dataKind = dataKind
    self.data = data
  }
}

public struct BuildClientCapabilities: Codable, Hashable, Sendable {
  /// The languages that this client supports.
  /// The ID strings for each language is defined in the LSP.
  /// The server must never respond with build targets for other
  /// languages than those that appear in this list.
  public var languageIds: [Language]

  /// Mirror capability to BuildServerCapabilities.jvmCompileClasspathProvider
  /// The client will request classpath via `buildTarget/jvmCompileClasspath` so
  /// it's safe to return classpath in ScalacOptionsItem empty. */
  public var jvmCompileClasspathReceiver: Bool?

  public init(languageIds: [Language], jvmCompileClasspathReceiver: Bool? = nil) {
    self.languageIds = languageIds
    self.jvmCompileClasspathReceiver = jvmCompileClasspathReceiver
  }
}

public struct InitializeBuildRequestDataKind: RawRepresentable, Hashable, Codable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

public struct InitializeBuildResponse: ResponseType, Hashable {
  /// Name of the server
  public var displayName: String

  /// The version of the server
  public var version: String

  /// The BSP version that the server speaks
  public var bspVersion: String

  /// The capabilities of the build server
  public var capabilities: BuildServerCapabilities

  /// Kind of data to expect in the `data` field. If this field is not set, the kind of data is not specified.
  public var dataKind: InitializeBuildResponseDataKind?

  /// Optional metadata about the server
  public var data: LSPAny?

  public init(
    displayName: String,
    version: String,
    bspVersion: String,
    capabilities: BuildServerCapabilities,
    dataKind: InitializeBuildResponseDataKind? = nil,
    data: LSPAny? = nil
  ) {
    self.displayName = displayName
    self.version = version
    self.bspVersion = bspVersion
    self.capabilities = capabilities
    self.dataKind = dataKind
    self.data = data
  }
}

public struct BuildServerCapabilities: Codable, Hashable, Sendable {
  /// The languages the server supports compilation via method buildTarget/compile.
  public var compileProvider: CompileProvider?

  /// The languages the server supports test execution via method buildTarget/test
  public var testProvider: TestProvider?

  /// The languages the server supports run via method buildTarget/run
  public var runProvider: RunProvider?

  /// The languages the server supports debugging via method debugSession/start.
  public var debugProvider: DebugProvider?

  /// The server can provide a list of targets that contain a
  /// single text document via the method buildTarget/inverseSources
  public var inverseSourcesProvider: Bool?

  /// The server provides sources for library dependencies
  /// via method buildTarget/dependencySources
  public var dependencySourcesProvider: Bool?

  /// The server provides all the resource dependencies
  /// via method buildTarget/resources
  public var resourcesProvider: Bool?

  /// The server provides all output paths
  /// via method buildTarget/outputPaths
  public var outputPathsProvider: Bool?

  /// The server sends notifications to the client on build
  /// target change events via `buildTarget/didChange`
  public var buildTargetChangedProvider: Bool?

  /// The server can respond to `buildTarget/jvmRunEnvironment` requests with the
  /// necessary information required to launch a Java process to run a main class.
  public var jvmRunEnvironmentProvider: Bool?

  /// The server can respond to `buildTarget/jvmTestEnvironment` requests with the
  /// necessary information required to launch a Java process for testing or
  /// debugging.
  public var jvmTestEnvironmentProvider: Bool?

  /// The server can respond to `workspace/cargoFeaturesState` and
  /// `setCargoFeatures` requests. In other words, supports Cargo Features extension.
  public var cargoFeaturesProvider: Bool?

  /// Reloading the build state through workspace/reload is supported
  public var canReload: Bool?

  /// The server can respond to `buildTarget/jvmCompileClasspath` requests with the
  /// necessary information about the target's classpath.
  public var jvmCompileClasspathProvider: Bool?

  public init(
    compileProvider: CompileProvider? = nil,
    testProvider: TestProvider? = nil,
    runProvider: RunProvider? = nil,
    debugProvider: DebugProvider? = nil,
    inverseSourcesProvider: Bool? = nil,
    dependencySourcesProvider: Bool? = nil,
    resourcesProvider: Bool? = nil,
    outputPathsProvider: Bool? = nil,
    buildTargetChangedProvider: Bool? = nil,
    jvmRunEnvironmentProvider: Bool? = nil,
    jvmTestEnvironmentProvider: Bool? = nil,
    cargoFeaturesProvider: Bool? = nil,
    canReload: Bool? = nil,
    jvmCompileClasspathProvider: Bool? = nil
  ) {
    self.compileProvider = compileProvider
    self.testProvider = testProvider
    self.runProvider = runProvider
    self.debugProvider = debugProvider
    self.inverseSourcesProvider = inverseSourcesProvider
    self.dependencySourcesProvider = dependencySourcesProvider
    self.resourcesProvider = resourcesProvider
    self.outputPathsProvider = outputPathsProvider
    self.buildTargetChangedProvider = buildTargetChangedProvider
    self.jvmRunEnvironmentProvider = jvmRunEnvironmentProvider
    self.jvmTestEnvironmentProvider = jvmTestEnvironmentProvider
    self.cargoFeaturesProvider = cargoFeaturesProvider
    self.canReload = canReload
    self.jvmCompileClasspathProvider = jvmCompileClasspathProvider
  }
}

public struct CompileProvider: Codable, Hashable, Sendable {
  public var languageIds: [Language]

  public init(languageIds: [Language]) {
    self.languageIds = languageIds
  }
}

public struct TestProvider: Codable, Hashable, Sendable {
  public var languageIds: [Language]

  public init(languageIds: [Language]) {
    self.languageIds = languageIds
  }
}

public struct RunProvider: Codable, Hashable, Sendable {
  public var languageIds: [Language]

  public init(languageIds: [Language]) {
    self.languageIds = languageIds
  }
}

public struct DebugProvider: Codable, Hashable, Sendable {
  public var languageIds: [Language]

  public init(languageIds: [Language]) {
    self.languageIds = languageIds
  }
}

public struct InitializeBuildResponseDataKind: RawRepresentable, Hashable, Codable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// `data` field must contain a `SourceKitInitializeBuildResponseData` object.
  public static let sourceKit = InitializeBuildResponseDataKind(rawValue: "sourceKit")
}

public struct SourceKitInitializeBuildResponseData: LSPAnyCodable, Codable, Sendable {
  /// The directory to which the index store is written during compilation, ie. the path passed to `-index-store-path`
  /// for `swiftc` or `clang` invocations
  public var indexDatabasePath: String?

  /// The path at which SourceKit-LSP can store its index database, aggregating data from `indexStorePath`
  public var indexStorePath: String?

  /// Whether the server implements the `buildTarget/outputPaths` request.
  public var outputPathsProvider: Bool?

  /// Whether the build server supports the `buildTarget/prepare` request.
  public var prepareProvider: Bool?

  /// Whether the server implements the `textDocument/sourceKitOptions` request.
  public var sourceKitOptionsProvider: Bool?

  /// The files to watch for changes.
  public var watchers: [FileSystemWatcher]?

  @available(*, deprecated, message: "Use initializer with alphabetical order of parameters")
  @_disfavoredOverload
  public init(
    indexDatabasePath: String? = nil,
    indexStorePath: String? = nil,
    watchers: [FileSystemWatcher]? = nil,
    prepareProvider: Bool? = nil,
    sourceKitOptionsProvider: Bool? = nil
  ) {
    self.indexDatabasePath = indexDatabasePath
    self.indexStorePath = indexStorePath
    self.watchers = watchers
    self.prepareProvider = prepareProvider
    self.sourceKitOptionsProvider = sourceKitOptionsProvider
  }

  public init(
    indexDatabasePath: String? = nil,
    indexStorePath: String? = nil,
    outputPathsProvider: Bool? = nil,
    prepareProvider: Bool? = nil,
    sourceKitOptionsProvider: Bool? = nil,
    watchers: [FileSystemWatcher]? = nil
  ) {
    self.indexDatabasePath = indexDatabasePath
    self.indexStorePath = indexStorePath
    self.outputPathsProvider = outputPathsProvider
    self.prepareProvider = prepareProvider
    self.sourceKitOptionsProvider = sourceKitOptionsProvider
    self.watchers = watchers
  }

  public init?(fromLSPDictionary dictionary: [String: LanguageServerProtocol.LSPAny]) {
    if case .string(let indexDatabasePath) = dictionary[CodingKeys.indexDatabasePath.stringValue] {
      self.indexDatabasePath = indexDatabasePath
    }
    if case .string(let indexStorePath) = dictionary[CodingKeys.indexStorePath.stringValue] {
      self.indexStorePath = indexStorePath
    }
    if case .bool(let outputPathsProvider) = dictionary[CodingKeys.outputPathsProvider.stringValue] {
      self.outputPathsProvider = outputPathsProvider
    }
    if case .bool(let prepareProvider) = dictionary[CodingKeys.prepareProvider.stringValue] {
      self.prepareProvider = prepareProvider
    }
    if case .bool(let sourceKitOptionsProvider) = dictionary[CodingKeys.sourceKitOptionsProvider.stringValue] {
      self.sourceKitOptionsProvider = sourceKitOptionsProvider
    }
    if let watchers = dictionary[CodingKeys.watchers.stringValue] {
      self.watchers = [FileSystemWatcher](fromLSPArray: watchers)
    }
  }

  public func encodeToLSPAny() -> LanguageServerProtocol.LSPAny {
    var result: [String: LSPAny] = [:]
    if let indexDatabasePath {
      result[CodingKeys.indexDatabasePath.stringValue] = .string(indexDatabasePath)
    }
    if let indexStorePath {
      result[CodingKeys.indexStorePath.stringValue] = .string(indexStorePath)
    }
    if let outputPathsProvider {
      result[CodingKeys.outputPathsProvider.stringValue] = .bool(outputPathsProvider)
    }
    if let prepareProvider {
      result[CodingKeys.prepareProvider.stringValue] = .bool(prepareProvider)
    }
    if let sourceKitOptionsProvider {
      result[CodingKeys.sourceKitOptionsProvider.stringValue] = .bool(sourceKitOptionsProvider)
    }
    if let watchers {
      result[CodingKeys.watchers.stringValue] = watchers.encodeToLSPAny()
    }
    return .dictionary(result)
  }
}
