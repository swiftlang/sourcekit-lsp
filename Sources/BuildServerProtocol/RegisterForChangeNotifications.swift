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
import LanguageServerProtocol

/// The register for changes request is sent from the language
/// server to the build server to register or unregister for
/// changes in file options or dependencies. On changes a
/// FileOptionsChangedNotification is sent.
public struct RegisterForChanges: RequestType {
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

public enum RegisterAction: String, Hashable, Codable {
  case register = "register"
  case unregister = "unregister"
}

/// The FileOptionsChangedNotification is sent from the
/// build server to the language server when it detects
/// changes to a registered files build settings.
public struct FileOptionsChangedNotification: NotificationType {
  public static let method: String = "build/sourceKitOptionsChanged"

  /// The URI of the document that has changed settings.
  public var uri: URI

  /// The updated options for the registered file.
  public var updatedOptions: SourceKitOptionsResult
}
