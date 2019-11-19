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
public struct BuildTargets: RequestType, Hashable {
  public static let method: String = "workspace/buildTargets"
  public typealias Response = BuildTargetsResult

  public init() {}
}

public struct BuildTargetsResult: ResponseType, Hashable {
  public var targets: [BuildTarget]
}

public struct BuildTarget: Codable, Hashable {
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

  /// The capabilities of this build target.
  public var capabilities: BuildTargetCapabilities

  /// The set of languages that this target contains.
  /// The ID string for each language is defined in the LSP.
  public var languageIds: [Language]

  /// The direct upstream build target dependencies of this build target
  public var dependencies: [BuildTargetIdentifier]

  public init(id: BuildTargetIdentifier,
              displayName: String?,
              baseDirectory: URI?,
              tags: [BuildTargetTag],
              capabilities: BuildTargetCapabilities,
              languageIds: [Language],
              dependencies: [BuildTargetIdentifier]) {
    self.id = id
    self.displayName = displayName
    self.baseDirectory = baseDirectory
    self.tags = tags
    self.capabilities = capabilities
    self.languageIds = languageIds
    self.dependencies = dependencies
  }
}

public struct BuildTargetIdentifier: Codable, Hashable {
  public var uri: URI

  public init(uri: URI) {
    self.uri = uri
  }
}

public struct BuildTargetTag: Codable, Hashable, RawRepresentable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Target contains re-usable functionality for downstream targets. May have
  /// any combination of capabilities.
  public static let library: Self = Self(rawValue: "library")

  /// Target contains source code for producing any kind of application, may
  /// have but does not require the `canRun` capability.
  public static let application: Self = Self(rawValue: "application")

  /// Target contains source code for testing purposes, may have but does not
  /// require the `canTest` capability.
  public static let test: Self = Self(rawValue: "test")

  /// Target contains source code for integration testing purposes, may have
  /// but does not require the `canTest` capability. The difference between
  /// "test" and "integration-test" is that integration tests traditionally run
  /// slower compared to normal tests and require more computing resources to
  /// execute.
  public static let integationTest: Self = Self(rawValue: "integration-test")

  /// Target contains source code to measure performance of a program, may have
  /// but does not require the `canRun` build target capability.
  public static let benchmark: Self = Self(rawValue: "benchmark")

  /// Target should be ignored by IDEs.
  public static let noIDE: Self = Self(rawValue: "no-ide")
}

public struct BuildTargetCapabilities: Codable, Hashable {
  /// This target can be compiled by the BSP server.
  public var canCompile: Bool

  /// This target can be tested by the BSP server.
  public var canTest: Bool

  /// This target can be run by the BSP server.
  public var canRun: Bool

  public init(canCompile: Bool, canTest: Bool, canRun: Bool) {
    self.canCompile = canCompile
    self.canTest = canTest
    self.canRun = canRun
  }
}

/// The build target sources request is sent from the client to the server to
/// query for the list of text documents and directories that are belong to a
/// build target. The sources response must not include sources that are
/// external to the workspace.
public struct BuildTargetSources: RequestType, Hashable {
  public static let method: String = "buildTarget/sources"
  public typealias Response = BuildTargetSourcesResult

  public var targets: [BuildTargetIdentifier]

  public init(targets: [BuildTargetIdentifier]) {
    self.targets = targets
  }
}

public struct BuildTargetSourcesResult: ResponseType, Hashable {
  public var items: [SourcesItem]
}

public struct SourcesItem: Codable, Hashable {
  public var target: BuildTargetIdentifier

  /// The text documents and directories that belong to this build target.
  public var sources: [SourceItem]
}

public struct SourceItem: Codable, Hashable {
  /// Either a text document or a directory. A directory entry must end with a
  /// forward slash "/" and a directory entry implies that every nested text
  /// document within the directory belongs to this source item.
  public var uri: URI

  /// Type of file of the source item, such as whether it is file or directory.
  public var kind: SourceItemKind

  /// Indicates if this source is automatically generated by the build and is
  /// not intended to be manually edited by the user.
  public var generated: Bool
}

public enum SourceItemKind: Int, Codable, Hashable {
  /// The source item references a normal file.
  case file = 1

  /// The source item references a directory.
  case directory = 2
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

public struct OutputsItem: Codable, Hashable {
  public var target: BuildTargetIdentifier

  /// The output paths for sources that belong to this build target.
  public var outputPaths: [URI]
}

/// The build target changed notification is sent from the server to the client
/// to signal a change in a build target. The server communicates during the
/// initialize handshake whether this method is supported or not.
public struct BuildTargetsChangedNotification: NotificationType {
  public static let method: String = "buildTarget/didChange"

  public var changes: [BuildTargetEvent]

  public init(changes: [BuildTargetEvent]) {
    self.changes = changes
  }
}

public struct BuildTargetEvent: Codable, Hashable {
  /// The identifier for the changed build target.
  public var target: BuildTargetIdentifier

  /// The kind of change for this build target.
  public var kind: BuildTargetEventKind?

  /// Any additional metadata about what information changed.
  public var data: LSPAny?

  public init(target: BuildTargetIdentifier, kind: BuildTargetEventKind?, data: LSPAny?) {
    self.target = target
    self.kind = kind
    self.data = data
  }
}

public enum BuildTargetEventKind: Int, Codable, Hashable {
  /// The build target is new.
  case created = 1

  /// The build target has changed.
  case changed = 2

  /// The build target has been deleted.
  case deleted = 3
}
