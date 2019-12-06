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

/// Request from the server for the set of currently open workspace folders.
///
///
/// Clients that support workspace folders should set the `workspaceFolders` client capability.
///
/// - Returns: The set of currently open workspace folders. Returns nil if only a single file is
///   open. Returns an empty array if a workspace is open but no folders are configured.
public struct WorkspaceFoldersRequest: RequestType, Hashable {
    public static let method: String = "workspace/workspaceFolders"
    public typealias Response = [WorkspaceFolder]?
}
