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
import LanguageServerProtocol

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
public struct InitializeBuild: RequestType, Hashable {
  public static let method: String = "build/initialize"
  public typealias Response = InitializeBuildResult

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

  public init(displayName: String, version: String, bspVersion: String, rootUri: URI, capabilities: BuildClientCapabilities) {
    self.displayName = displayName
    self.version = version
    self.bspVersion = bspVersion
    self.rootUri = rootUri
    self.capabilities = capabilities
  }
}

public struct BuildClientCapabilities: Codable, Hashable {
  /// The languages that this client supports.
  /// The ID strings for each language is defined in the LSP.
  /// The server must never respond with build targets for other
  /// languages than those that appear in this list.
  public var languageIds: [Language]

  public init(languageIds: [Language]) {
    self.languageIds = languageIds
  }
}

public struct InitializeBuildResult: ResponseType, Hashable {
  /// Name of the server 
  public var displayName: String

  /// The version of the server 
  public var version: String

  /// The BSP version that the server speaks 
  public var bspVersion: String

  /// The capabilities of the build server 
  public var capabilities: BuildServerCapabilities

  /// Optional metadata about the server
  public var data: LSPAny?

  public init(displayName: String, version: String, bspVersion: String, capabilities: BuildServerCapabilities, data: LSPAny? = nil) {
    self.displayName = displayName
    self.version = version
    self.bspVersion = bspVersion
    self.capabilities = capabilities
    self.data = data
  }
}

public struct BuildServerCapabilities: Codable, Hashable {
  /// The languages the server supports compilation via method buildTarget/compile.
  public var compileProvider: CompileProvider? = nil

  /// The languages the server supports test execution via method buildTarget/test
  public var testProvider: TestProvider? = nil

  /// The languages the server supports run via method buildTarget/run
  public var runProvider: RunProvider? = nil

  /// The server can provide a list of targets that contain a
  /// single text document via the method buildTarget/inverseSources
  public var inverseSourcesProvider: Bool? = nil

  /// The server provides sources for library dependencies
  /// via method buildTarget/dependencySources
  public var dependencySourcesProvider: Bool? = nil

  /// The server provides all the resource dependencies
  /// via method buildTarget/resources
  public var resourcesProvider: Bool? = nil

  /// The server sends notifications to the client on build
  /// target change events via buildTarget/didChange
  public var buildTargetChangedProvider: Bool? = nil
}

public struct CompileProvider: Codable, Hashable {
  public var languageIds: [Language]

  public init(languageIds: [Language]) {
    self.languageIds = languageIds
  }
}

public struct RunProvider: Codable, Hashable {
  public var languageIds: [Language]

  public init(languageIds: [Language]) {
    self.languageIds = languageIds
  }
}

public struct TestProvider: Codable, Hashable {
  public var languageIds: [Language]

  public init(languageIds: [Language]) {
    self.languageIds = languageIds
  }
}

public struct InitializedBuildNotification: NotificationType {
  public static let method: String = "build/initialized"

  public init() {}
}
