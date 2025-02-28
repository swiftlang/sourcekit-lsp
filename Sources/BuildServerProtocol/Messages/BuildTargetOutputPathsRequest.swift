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
public import LanguageServerProtocol
#else
import LanguageServerProtocol
#endif

/// For all the source files in this target, the output paths that are used during indexing, ie. the
/// `-index-unit-output-path` for the file, if it is specified in the compiler arguments or the file that is passed as
/// `-o`, if `-index-unit-output-path` is not specified.
public struct BuildTargetOutputPathsRequest: RequestType, Equatable, Hashable {
  public static let method: String = "buildTarget/outputPaths"

  public typealias Response = BuildTargetOutputPathsResponse

  /// A list of build targets to get the output paths for.
  public var targets: [BuildTargetIdentifier]

  public init(targets: [BuildTargetIdentifier]) {
    self.targets = targets
  }
}

public struct BuildTargetOutputPathsItem: Codable, Sendable {
  /// The target these output file paths are for.
  public var target: BuildTargetIdentifier

  /// The output paths for all source files in this target.
  public var outputPaths: [String]

  public init(target: BuildTargetIdentifier, outputPaths: [String]) {
    self.target = target
    self.outputPaths = outputPaths
  }
}

public struct BuildTargetOutputPathsResponse: ResponseType {
  public var items: [BuildTargetOutputPathsItem]

  public init(items: [BuildTargetOutputPathsItem]) {
    self.items = items
  }
}
