//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

package struct PathPrefixMapping: Sendable {
  /// Path prefix to be replaced, typically the canonical or hermetic path.
  package let original: String

  /// Replacement path prefix, typically the path on the local machine.
  package let replacement: String

  package init(original: String, replacement: String) {
    self.original = original
    self.replacement = replacement
  }
}
