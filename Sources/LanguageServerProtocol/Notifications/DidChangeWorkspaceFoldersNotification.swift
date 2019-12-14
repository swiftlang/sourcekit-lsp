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

/// Notification from the client that the set of open workspace folders has changed.
///
/// - Parameter event: The set of changes.
///
/// Requires the `workspaceFolders` capability on both the client and server.
public struct DidChangeWorkspaceFoldersNotification: NotificationType {
    public static let method: String = "workspace/didChangeWorkspaceFolders"

    /// The set of changes.
    public var event: WorkspaceFoldersChangeEvent

    public init(event: WorkspaceFoldersChangeEvent) {
        self.event = event
    }
}

/// The workspace folder change event.
public struct WorkspaceFoldersChangeEvent: Codable, Hashable {

    /// The array of added workspace folders
    public var added: [WorkspaceFolder]?

    /// The array of the removed workspace folders
    public var removed: [WorkspaceFolder]?

    public init(added: [WorkspaceFolder]? = nil, removed: [WorkspaceFolder]? = nil) {
        self.added = added
        self.removed = removed
    }
}
