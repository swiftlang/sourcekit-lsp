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

import Foundation
import Utility
import PackageModel

/// Server configuration
public struct ServerConfiguration: Configuration {

  public static let `default` = ServerConfiguration(build: ServerConfiguration.Build(configuration: .debug,
                                                                                     path: "./.build",
                                                                                     flags: BuildFlags()))

  public struct Build: SKCore.BuildConfiguration {
    /// Build configuration
    public let configuration: PackageModel.BuildConfiguration

    /// Build artefacts directory path
    public let path: String

    /// Additional build flags
    public let flags: BuildFlags

    public init(configuration: PackageModel.BuildConfiguration, path: String, flags: BuildFlags) {
      self.configuration = configuration
      self.path = path
      self.flags = flags
    }
  }

  /// Build related configuration
  public let build: SKCore.BuildConfiguration

  public init(build: Build) {
    self.build = build
  }
}
