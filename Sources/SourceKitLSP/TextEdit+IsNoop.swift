//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

extension TextEdit {
  /// Returns `true` the replaced text is the same as the new text
  func isNoOp(in snapshot: DocumentSnapshot) -> Bool {
    if snapshot.text[snapshot.indexRange(of: range)] == newText {
      return true
    }
    return false
  }
}
