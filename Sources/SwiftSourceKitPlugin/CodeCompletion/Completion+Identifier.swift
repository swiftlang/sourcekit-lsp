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
  /// A unique identifier for the completion within a given session.
  struct Identifier: Hashable {
    /// The index of this completion item within the code completion session.
    let index: UInt32

    init(index: UInt32) {
      self.index = index
    }

    /// Restore an `Identifier` from a value retrieved from `opaqueValue`.
    init(opaqueValue: Int64) {
      self.init(index: UInt32(bitPattern: Int32(opaqueValue)))
    }

    /// Representation of this identifier as an `Int64`, which can be transferred in sourcekitd requests.
    var opaqueValue: Int64 {
      Int64(bitPattern: UInt64(index))
    }
  }
}
