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

#if compiler(>=6)
package import Foundation
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
#else
import Foundation
import ToolchainRegistry

import struct TSCBasic.AbsolutePath
#endif

extension Toolchain {
  /// The path to `swift-frontend` in the toolchain, found relative to `swift`.
  ///
  /// - Note: Not discovered as part of the toolchain because `swift-frontend` is only needed in the diagnose commands.
  package var swiftFrontend: URL? {
    return swift?.deletingLastPathComponent().appendingPathComponent("swift-frontend")
  }
}
