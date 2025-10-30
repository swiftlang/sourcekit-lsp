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

public import LanguageServerProtocol

/// The register for changes request is sent from the language
/// server to the build server to register or unregister for
/// changes in file options or dependencies. On changes a
/// FileOptionsChangedNotification is sent.
///
/// - Important: This request has been deprecated. Build servers should instead implement the
///   `textDocument/sourceKitOptions` request.
///   See https://forums.swift.org/t/extending-functionality-of-build-server-protocol-with-sourcekit-lsp/74400
public struct RegisterForChanges: BSPRequest {
  public static let method: String = "textDocument/registerForChanges"
  public typealias Response = VoidResponse

  /// The URI of the document to get options for.
  public var uri: URI

  /// Whether to register or unregister for the file.
  public var action: RegisterAction

  public init(uri: URI, action: RegisterAction) {
    self.uri = uri
    self.action = action
  }
}

public enum RegisterAction: String, Hashable, Codable, Sendable {
  case register = "register"
  case unregister = "unregister"
}

/// The FileOptionsChangedNotification is sent from the
/// build server to the language server when it detects
/// changes to a registered files build settings.
///
/// - Important: This request has been deprecated. Build servers should instead implement the
///   `textDocument/sourceKitOptions` request.
///   See https://forums.swift.org/t/extending-functionality-of-build-server-protocol-with-sourcekit-lsp/74400
public struct FileOptionsChangedNotification: BSPNotification {
  public struct Options: ResponseType, Hashable {
    /// The compiler options required for the requested file.
    public var options: [String]

    /// The working directory for the compile command.
    public var workingDirectory: String?
  }

  public static let method: String = "build/sourceKitOptionsChanged"

  /// The URI of the document that has changed settings.
  public var uri: URI

  /// The updated options for the registered file.
  public var updatedOptions: Options
}
