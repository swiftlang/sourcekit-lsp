//
//  ServerConfiguration.swift
//  SourceKitLSP
//
//  Created by Marcin Krzyzanowski on 11/01/2019.
//

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
