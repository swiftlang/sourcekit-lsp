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
import BuildServerProtocol
import LanguageServerProtocol
import TSCBasic

/// Handles  build system events, such as file build settings changes.
public protocol BuildSystemDelegate: AnyObject {
  /// Notify the delegate that the build targets have changed.
  ///
  /// The callee should request new sources and outputs for the build targets of
  /// interest.
  func buildTargetsChanged(_ changes: [BuildTargetEvent])

  /// Notify the delegate that the given files' build settings have changed.
  ///
  /// The callee should request new build settings for any of the given files
  /// that they are interested in.
  func fileBuildSettingsChanged(_ changedFiles: Set<URL>)
}
