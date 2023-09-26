//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import BuildServerProtocol
import LanguageServerProtocol

import struct TSCBasic.AbsolutePath

/// Defines how well a `BuildSystem` can handle a file with a given URI.
public enum FileHandlingCapability: Comparable {
  /// The build system can't handle the file at all
  case unhandled

  /// The build system has fallback build settings for the file
  case fallback

  /// The build system knows how to handle the file
  case handled
}

/// Provider of FileBuildSettings and other build-related information.
///
/// The primary role of the build system is to answer queries for
/// FileBuildSettings and to notify its delegate when they change. The
/// BuildSystem is also the source of related information, such as where the
/// index datastore is located.
///
/// For example, a SwiftPMWorkspace provides compiler arguments for the files
/// contained in a SwiftPM package root directory.
public protocol BuildSystem: AnyObject {

  /// The path to the raw index store data, if any.
  var indexStorePath: AbsolutePath? { get }

  /// The path to put the index database, if any.
  var indexDatabasePath: AbsolutePath? { get }

  /// Path remappings for remapping index data for local use.
  var indexPrefixMappings: [PathPrefixMapping] { get }

  /// Delegate to handle any build system events such as file build settings
  /// initial reports as well as changes.
  var delegate: BuildSystemDelegate? { get set }

  /// Register the given file for build-system level change notifications, such
  /// as command line flag changes, dependency changes, etc.
  ///
  /// IMPORTANT: When first receiving a register request, the `BuildSystem` MUST asynchronously
  /// inform its delegate of any initial settings for the given file via the
  /// `fileBuildSettingsChanged` method, even if unavailable.
  func registerForChangeNotifications(for: DocumentURI, language: Language)

  /// Unregister the given file for build-system level change notifications,
  /// such as command line flag changes, dependency changes, etc.
  func unregisterForChangeNotifications(for: DocumentURI)

  /// Called when files in the project change.
  func filesDidChange(_ events: [FileEvent])

  func fileHandlingCapability(for uri: DocumentURI) -> FileHandlingCapability
}

public let buildTargetsNotSupported =
  ResponseError.methodNotFound(BuildTargets.method)
