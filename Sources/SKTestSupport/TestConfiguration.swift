//
//  TestConfiguration.swift
//  SourceKitLSP
//
//  Created by Marcin Krzyzanowski on 11/01/2019.
//

import Foundation
import Utility
import PackageModel
@testable import SKCore

public struct TestConfiguration: Configuration {

  public static let `default`: TestConfiguration = TestConfiguration(build: TestConfiguration.Build())

  public struct Build: SKCore.BuildConfiguration {
    /// Build configuration
    public let configuration: PackageModel.BuildConfiguration = .debug

    /// Build artefacts directory name
    public let path: String = ".build"

    /// Additional build flags
    public let flags: BuildFlags = BuildFlags()
  }

  public let build: SKCore.BuildConfiguration

  public init(build: Build) {
    self.build = build
  }
}
