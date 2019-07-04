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

/// The failure handling strategy of a client if applying the workspace edit fails
public enum FailureHandlingKind: String, Codable, Hashable {
    /// Applying the workspace change is simply aborted if one of the changes provided
    /// fails. All operations executed before the failing operation stay executed.
    case abort

    /// All operations are executed transactionally. That means they either all
    /// succeed or no changes at all are applied to the workspace.
    case transactional

    /// If the workspace edit contains only textual file changes they are executed transactionally.
    /// If resource changes (create, rename or delete file) are part of the change the failure
    /// handling strategy is abort.
    case textOnlyTransactional

    /// The client tries to undo the operations already executed. But there is no
    /// guarantee that this succeeds.
    case undo
}
