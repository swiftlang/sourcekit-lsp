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

/// The kind of resource operations supported by the client.
public enum ResourceOperationKind: String, Codable, Hashable {
    /// Supports creating new resources.
    case create

    /// Supports renaming existing resources.
    case rename

    /// Supports deleting existing resources.
    case delete
}
