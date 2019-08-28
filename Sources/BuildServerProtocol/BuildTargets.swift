import LanguageServerProtocol

/// The workspace build targets request is sent from the client
/// to the server to ask for the list of all available build
/// targets in the workspace.
public struct BuildTargets: RequestType, Hashable {
  public static let method: String = "workspace/buildTargets"
  public typealias Response = BuildTargetsResult
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

  /// The directory where this target belongs to. Multiple build targets are allowed to map
  /// to the same base directory, and a build target is not required to have a base directory.
  /// A base directory does not determine the sources of a target, see buildTarget/sources. 
  public var baseDirectory: URL?

  /// Free-form string tags to categorize or label this build target.
  /// For example, can be used by the client to:
  /// - customize how the target should be translated into the client's project model.
  /// - group together different but related targets in the user interface.
  /// - display icons or colors in the user interface.
  /// Pre-defined tags are listed in `BuildTargetTag` but clients and servers
  /// are free to define new tags for custom purposes.
  public var tags: [String]

  /// The capabilities of this build target. 
  public var capabilities: BuildTargetCapabilities

  /// The set of languages that this target contains.
  /// The ID string for each language is defined in the LSP. 
  public var languageIds: [String]

  /// The direct upstream build target dependencies of this build target 
  public var dependencies: [BuildTargetIdentifier]
}

public struct BuildTargetIdentifier: Codable, Hashable {
  public var uri: URL
}

public enum BuildTargetTag: String {
  /// Target contains re-usable functionality for downstream targets. May have any
   /// combination of capabilities. 
   case Library = "library"

   /// Target contains source code for producing any kind of application, may have
   /// but does not require the `canRun` capability. 
   case Application = "application"

   /// Target contains source code for testing purposes, may have but does not
   /// require the `canTest` capability. 
   case Test = "test"

   /// Target contains source code for integration testing purposes, may have
   /// but does not require the `canTest` capability.
   /// The difference between "test" and "integration-test" is that
   /// integration tests traditionally run slower compared to normal tests
   /// and require more computing resources to execute.
   case IntegrationTest = "integration-test"

   /// Target contains source code to measure performance of a program, may have
   /// but does not require the `canRun` build target capability.
   case Benchmark = "benchmark"

   /// Target should be ignored by IDEs. 
   case NoIDE = "no-ide"
}

public struct BuildTargetCapabilities: Codable, Hashable {
  /// This target can be compiled by the BSP server. 
  public var canCompile: Bool

  /// This target can be tested by the BSP server. 
  public var canTest: Bool

  /// This target can be run by the BSP server. 
  public var canRun: Bool
}
