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

/// Notification from the client that the configuration of the workspace has changed.
///
/// - Note: the format of the settings is implementation-defined.
///
/// - Parameter settings: The changed workspace settings.
public struct DidChangeConfigurationNotification: NotificationType {
  public static let method: String = "workspace/didChangeConfiguration"

  /// The changed workspace settings.
  public var settings: WorkspaceSettingsChange

  public init(settings: WorkspaceSettingsChange) {
    self.settings = settings
  }
}
