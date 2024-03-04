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

/// Code-completion configuration.
///
/// **(LSP Extension)**: This is used as part of an extension to the
/// code-completion request.
public struct SKCompletionOptions: Codable, Hashable, Sendable {
  /// The maximum number of completion results to return, or `nil` for unlimited.
  public var maxResults: Int?

  /// Older `sourcekit-lsp` binaries reject request sent from client to
  /// server when the parameter is missing. By adding the parameter with default
  /// value true the client that uses **LanguageServerProtocol** as model can still
  /// interact with shipped `sourcekit-lsp` instances.
  @available(*, deprecated, message: "Not used")
  public private(set) var serverSideFiltering: Bool = true

  public init(maxResults: Int? = 200) {
    self.maxResults = maxResults
  }
}
