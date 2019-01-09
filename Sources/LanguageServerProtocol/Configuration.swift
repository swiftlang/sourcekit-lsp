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

/// Request from the server to the client to fetch configuration settings from the client.
///
/// Clients that support workspace folders should set the `workspaceFolders` client capability.
///
/// - Note: the format of the settings is implementation-defined.
///
/// - Returns: Configuration settings. If the client can't provide a configuration setting for
///            a given scope then nil need to be present in the returned array.
public struct ConfigurationRequest: RequestType, Hashable {
    public static let method: String = "workspace/configuration"
    public typealias Response = [WorkspaceSettingsChange?]

    /// The order of the returned configuration settings correspond to the order of the items.
    public var items: [ConfigurationItem]
}

public struct ConfigurationItem: Codable, Hashable {
    /// The scope to get the configuration section for.
    public var scope: URL?

    /// The configuration section asked for.
    public var section: String?
}

/// Notification from the client that the configuration of the workspace has changed.
///
/// - Note: the format of the settings is implementation-defined.
///
/// - Parameter settings: The changed workspace settings.
public struct DidChangeConfiguration: NotificationType {
  public static let method: String = "workspace/didChangeConfiguration"

  /// The changed workspace settings.
  public var settings: WorkspaceSettingsChange

  public init(settings: WorkspaceSettingsChange) {
    self.settings = settings
  }
}
