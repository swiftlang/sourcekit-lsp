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

import TSCBasic
import TSCUtility
import SKSupport

/// Build configuration
public struct BuildSetup {

  /// Default configuration
  public static let `default` = BuildSetup(configuration: .debug,
                                           path: nil,
                                           flags: BuildFlags())

  /// Build configuration (debug|release).
  public var configuration: BuildConfiguration

  /// Build artefacts directory path. If nil, the build system may choose a default value.
  public var path: AbsolutePath?

  /// Additional build flags
  public var flags: BuildFlags

  public init(configuration: BuildConfiguration, path: AbsolutePath?, flags: BuildFlags) {
    self.configuration = configuration
    self.path = path
    self.flags = flags
  }
}
