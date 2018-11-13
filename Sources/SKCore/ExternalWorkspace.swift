//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basic

/// Connection to an external workspace/project, providing access to settings, etc.
///
/// For example, a swiftpm package loaded from disk can provide command-line arguments for the files
/// contained in its package root directory.
public protocol ExternalWorkspace {

  /// The build system, providing access to compiler arguments.
  var buildSystem: BuildSettingsProvider { get }

  /// The path to the raw index store data, if any.
  var indexStorePath: AbsolutePath? { get }

  /// The path to put the index database, if any.
  var indexDatabasePath: AbsolutePath? { get }
}