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
import SKSupport

/// Build configuration
public struct BuildSetup {

  /// Default configuration
  public static let `default` = BuildSetup(configuration: .debug,
                                           path: ".build",
                                           flags: BuildFlags())

  /// Build configuration
  public let configuration: BuildConfiguration

  /// Build artefacts directory path
  public let path: String

  /// Additional build flags
  public let flags: BuildFlags

  public init(configuration: BuildConfiguration, path: String, flags: BuildFlags) {
    self.configuration = configuration
    self.path = path
    self.flags = flags
  }
}
