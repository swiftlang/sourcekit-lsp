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
public enum FileHandlingCapability: Comparable, Sendable {
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
public protocol BuildSystem: AnyObject, Sendable {

  /// The root of the project that this build system manages. For example, for SwiftPM packages, this is the folder
  /// containing Package.swift. For compilation databases it is the root folder based on which the compilation database
  /// was found.
  var projectRoot: AbsolutePath { get async }

  /// The path to the raw index store data, if any.
  var indexStorePath: AbsolutePath? { get async }

  /// The path to put the index database, if any.
  var indexDatabasePath: AbsolutePath? { get async }

  /// Path remappings for remapping index data for local use.
  var indexPrefixMappings: [PathPrefixMapping] { get async }

  /// Delegate to handle any build system events such as file build settings initial reports as well as changes.
  ///
  /// The build system must not retain the delegate because the delegate can be the `BuildSystemManager`, which could
  /// result in a retain cycle `BuildSystemManager` -> `BuildSystem` -> `BuildSystemManager`.
  var delegate: BuildSystemDelegate? { get async }

  /// Set the build system's delegate.
  ///
  /// - Note: Needed so we can set the delegate from a different actor isolation
  ///   context.
  func setDelegate(_ delegate: BuildSystemDelegate?) async

  /// Retrieve build settings for the given document with the given source
  /// language.
  ///
  /// Returns `nil` if the build system can't provide build settings for this
  /// file or if it hasn't computed build settings for the file yet.
  func buildSettings(for document: DocumentURI, language: Language) async throws -> FileBuildSettings?

  /// Register the given file for build-system level change notifications, such
  /// as command line flag changes, dependency changes, etc.
  ///
  /// IMPORTANT: When first receiving a register request, the `BuildSystem` MUST asynchronously
  /// inform its delegate of any initial settings for the given file via the
  /// `fileBuildSettingsChanged` method, even if unavailable.
  func registerForChangeNotifications(for: DocumentURI) async

  /// Unregister the given file for build-system level change notifications,
  /// such as command line flag changes, dependency changes, etc.
  func unregisterForChangeNotifications(for: DocumentURI) async

  /// Called when files in the project change.
  func filesDidChange(_ events: [FileEvent]) async

  func fileHandlingCapability(for uri: DocumentURI) async -> FileHandlingCapability

  /// Returns the list of files that might contain test cases.
  ///
  /// The returned file list is an over-approximation. It might contain tests from non-test targets or files that don't
  /// actually contain any tests. Keeping this list as minimal as possible helps reduce the amount of work that the
  /// syntactic test indexer needs to perform.
  func testFiles() async -> [DocumentURI]

  /// Adds a callback that should be called when the value returned by `testFiles()` changes.
  ///
  /// The callback might also be called without an actual change to `testFiles`.
  func addTestFilesDidChangeCallback(_ callback: @Sendable @escaping () async -> Void) async
}

public let buildTargetsNotSupported =
  ResponseError.methodNotFound(BuildTargets.method)
