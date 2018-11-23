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

/// The workspace folder change event.
public struct WorkspaceFoldersChangeEvent: Codable, Hashable {

    /// The array of added workspace folders
    public var added: [WorkspaceFolder]?

    /// The array of the removed workspace folders
    public var removed: [WorkspaceFolder]?

    init(added: [WorkspaceFolder]? = nil, removed: [WorkspaceFolder]? = nil) {
        self.added = added
        self.removed = removed
    }
}