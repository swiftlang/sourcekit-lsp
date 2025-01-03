//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension CompletionItem {
  package enum TypeRelation {
    /// The result does not have a type (e.g. keyword).
    case notApplicable

    /// The type relation have not been calculated.
    case unknown

    /// The relationship of the result's type to the expected type is not
    /// invalid, not convertible, and not identical.
    case unrelated

    /// The result's type is invalid at the expected position.
    case invalid

    /// The result's type is convertible to the type of the expected.
    case convertible

    /// The result's type is identical to the type of the expected.
    case identical
  }
}
