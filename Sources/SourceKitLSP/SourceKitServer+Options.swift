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

import Foundation
import LanguageServerProtocol
import SKCore
import SKSupport

import struct TSCBasic.AbsolutePath

extension SourceKitServer {

  /// Configuration options for the SourceKitServer.
  public struct Options {

    /// Additional compiler flags (e.g. `-Xswiftc` for SwiftPM projects) and other build-related
    /// configuration.
    public var buildSetup: BuildSetup

    /// Additional arguments to pass to `clangd` on the command-line.
    public var clangdOptions: [String]

    /// Additional options for the index.
    public var indexOptions: IndexOptions

    /// Options for code-completion.
    public var completionOptions: SKCompletionOptions

    /// Override the default directory where generated interfaces will be stored
    public var generatedInterfacesPath: AbsolutePath

    /// The time that `SwiftLanguageServer` should wait after an edit before starting to compute diagnostics and sending
    /// a `PublishDiagnosticsNotification`.
    ///
    /// This is mostly intended for testing purposes so we don't need to wait the debouncing time to get a diagnostics
    /// notification when running unit tests.
    public var swiftPublishDiagnosticsDebounceDuration: TimeInterval

    public init(
      buildSetup: BuildSetup = .default,
      clangdOptions: [String] = [],
      indexOptions: IndexOptions = .init(),
      completionOptions: SKCompletionOptions = .init(),
      generatedInterfacesPath: AbsolutePath = defaultDirectoryForGeneratedInterfaces,
      swiftPublishDiagnosticsDebounceDuration: TimeInterval = 2 /* 2s */
    ) {
      self.buildSetup = buildSetup
      self.clangdOptions = clangdOptions
      self.indexOptions = indexOptions
      self.completionOptions = completionOptions
      self.generatedInterfacesPath = generatedInterfacesPath
      self.swiftPublishDiagnosticsDebounceDuration = swiftPublishDiagnosticsDebounceDuration
    }
  }
}
