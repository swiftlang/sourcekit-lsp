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

public typealias URI = DocumentURI

/// The workspace build targets request is sent from the client to the server to
/// ask for the list of all available build targets in the workspace.
public struct BuildTargetsRequest: RequestType, Hashable {
  public static let method: String = "workspace/buildTargets"
  public typealias Response = BuildTargetsResponse

  public init() {}
}

public struct BuildTargetsResponse: ResponseType, Hashable {
  public var targets: [BuildTarget]

  public init(targets: [BuildTarget]) {
    self.targets = targets
  }
}

public struct BuildTarget: Codable, Hashable, Sendable {
  /// The target’s unique identifier
  public var id: BuildTargetIdentifier

  /// A human readable name for this target.
  /// May be presented in the user interface.
  /// Should be unique if possible.
  /// The id.uri is used if None.
  public var displayName: String?

  /// The directory where this target belongs to. Multiple build targets are
  /// allowed to map to the same base directory, and a build target is not
  /// required to have a base directory. A base directory does not determine the
  /// sources of a target, see buildTarget/sources.
  public var baseDirectory: URI?

  /// Free-form string tags to categorize or label this build target.
  /// For example, can be used by the client to:
  /// - customize how the target should be translated into the client's project
  ///   model.
  /// - group together different but related targets in the user interface.
  /// - display icons or colors in the user interface.
  /// Pre-defined tags are listed in `BuildTargetTag` but clients and servers
  /// are free to define new tags for custom purposes.
  public var tags: [BuildTargetTag]

  /// The set of languages that this target contains.
  /// The ID string for each language is defined in the LSP.
  public var languageIds: [Language]

  /// The direct upstream build target dependencies of this build target
  public var dependencies: [BuildTargetIdentifier]

  /// The capabilities of this build target.
  public var capabilities: BuildTargetCapabilities

  /// Kind of data to expect in the `data` field. If this field is not set, the kind of data is not specified.
  public var dataKind: BuildTargetDataKind?

  /// Language-specific metadata about this target.
  /// See ScalaBuildTarget as an example.
  public var data: LSPAny?

  public init(
    id: BuildTargetIdentifier,
    displayName: String?,
    baseDirectory: URI?,
    tags: [BuildTargetTag],
    capabilities: BuildTargetCapabilities,
    languageIds: [Language],
    dependencies: [BuildTargetIdentifier],
    dataKind: BuildTargetDataKind? = nil,
    data: LSPAny? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.baseDirectory = baseDirectory
    self.tags = tags
    self.capabilities = capabilities
    self.languageIds = languageIds
    self.dependencies = dependencies
    self.dataKind = dataKind
    self.data = data
  }
}

public struct BuildTargetIdentifier: Codable, Hashable, Sendable {
  public var uri: URI

  public init(uri: URI) {
    self.uri = uri
  }
}

public struct BuildTargetTag: Codable, Hashable, RawRepresentable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Target contains source code for producing any kind of application, may
  /// have but does not require the `canRun` capability.
  public static let application: Self = Self(rawValue: "application")

  /// Target contains source code to measure performance of a program, may have
  /// but does not require the `canRun` build target capability.
  public static let benchmark: Self = Self(rawValue: "benchmark")

  /// Target contains source code for integration testing purposes, may have
  /// but does not require the `canTest` capability. The difference between
  /// "test" and "integration-test" is that integration tests traditionally run
  /// slower compared to normal tests and require more computing resources to
  /// execute.
  public static let integrationTest: Self = Self(rawValue: "integration-test")

  /// Target contains re-usable functionality for downstream targets. May have
  /// any combination of capabilities.
  public static let library: Self = Self(rawValue: "library")

  /// Actions on the target such as build and test should only be invoked manually
  /// and explicitly. For example, triggering a build on all targets in the workspace
  /// should by default not include this target.
  /// The original motivation to add the "manual" tag comes from a similar functionality
  /// that exists in Bazel, where targets with this tag have to be specified explicitly
  /// on the command line.
  public static let manual: Self = Self(rawValue: "manual")

  /// Target should be ignored by IDEs.
  public static let noIDE: Self = Self(rawValue: "no-ide")

  /// Target contains source code for testing purposes, may have but does not
  /// require the `canTest` capability.
  public static let test: Self = Self(rawValue: "test")

  /// This is a target of a dependency from the project the user opened, eg. a target that builds a SwiftPM dependency.
  ///
  /// **(BSP Extension)**
  public static let dependency: Self = Self(rawValue: "dependency")

  /// This target only exists to provide compiler arguments for SourceKit-LSP can't be built standalone.
  ///
  /// For example, a SwiftPM package manifest is in a non-buildable target.
  public static let notBuildable: Self = Self(rawValue: "not-buildable")
}

public struct BuildTargetCapabilities: Codable, Hashable, Sendable {
  /// This target can be compiled by the BSP server.
  public var canCompile: Bool?

  /// This target can be tested by the BSP server.
  public var canTest: Bool?

  /// This target can be run by the BSP server.
  public var canRun: Bool?

  /// This target can be debugged by the BSP server.
  public var canDebug: Bool?

  public init(canCompile: Bool? = nil, canTest: Bool? = nil, canRun: Bool? = nil, canDebug: Bool? = nil) {
    self.canCompile = canCompile
    self.canTest = canTest
    self.canRun = canRun
    self.canDebug = canDebug
  }
}

public struct BuildTargetDataKind: RawRepresentable, Codable, Hashable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// `data` field must contain a CargoBuildTarget object.
  public static let cargo = BuildTargetDataKind(rawValue: "cargo")

  /// `data` field must contain a CppBuildTarget object.
  public static let cpp = BuildTargetDataKind(rawValue: "cpp")

  /// `data` field must contain a JvmBuildTarget object.
  public static let jvm = BuildTargetDataKind(rawValue: "jvm")

  /// `data` field must contain a PythonBuildTarget object.
  public static let python = BuildTargetDataKind(rawValue: "python")

  /// `data` field must contain a SbtBuildTarget object.
  public static let sbt = BuildTargetDataKind(rawValue: "sbt")

  /// `data` field must contain a ScalaBuildTarget object.
  public static let scala = BuildTargetDataKind(rawValue: "scala")

  /// `data` field must contain a SourceKitBuildTarget object.
  public static let sourceKit = BuildTargetDataKind(rawValue: "sourceKit")
}

public struct SourceKitBuildTarget: LSPAnyCodable, Codable {
  /// The toolchain that should be used to build this target. The URI should point to the directory that contains the
  /// `usr` directory. On macOS, this is typically a bundle ending in `.xctoolchain`. If the toolchain is installed to
  /// `/` on Linux, the toolchain URI would point to `/`.
  ///
  /// If no toolchain is given, SourceKit-LSP will pick a toolchain to use for this target.
  public var toolchain: URI?

  public init(toolchain: URI? = nil) {
    self.toolchain = toolchain
  }

  public init(fromLSPDictionary dictionary: [String: LanguageServerProtocol.LSPAny]) {
    if case .string(let toolchain) = dictionary[CodingKeys.toolchain.stringValue] {
      self.toolchain = try? URI(string: toolchain)
    }
  }

  public func encodeToLSPAny() -> LanguageServerProtocol.LSPAny {
    var result: [String: LSPAny] = [:]
    if let toolchain {
      result[CodingKeys.toolchain.stringValue] = .string(toolchain.stringValue)
    }
    return .dictionary(result)
  }
}

/// The build target output paths request is sent from the client to the server
/// to query for the list of compilation output paths for a targets sources.
public struct BuildTargetOutputPaths: RequestType, Hashable {
  public static let method: String = "buildTarget/outputPaths"
  public typealias Response = BuildTargetOutputPathsResponse

  public var targets: [BuildTargetIdentifier]

  public init(targets: [BuildTargetIdentifier]) {
    self.targets = targets
  }
}

public struct BuildTargetOutputPathsResponse: ResponseType, Hashable {
  public var items: [OutputsItem]
}

public struct OutputsItem: Codable, Hashable, Sendable {
  public var target: BuildTargetIdentifier

  /// The output paths for sources that belong to this build target.
  public var outputPaths: [URI]
}
