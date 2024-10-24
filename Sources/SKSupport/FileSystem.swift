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

#if compiler(>=6)
package import Foundation
import SwiftExtensions

package import struct TSCBasic.AbsolutePath
#else
import Foundation
import SwiftExtensions

import struct TSCBasic.AbsolutePath
#endif

extension AbsolutePath {
  /// Inititializes an absolute path from a string, expanding a leading `~` to `homeDirectoryForCurrentUser` first.
  package init(expandingTilde path: String) throws {
    if path.first == "~" {
      try self.init(
        AbsolutePath(validating: FileManager.default.homeDirectoryForCurrentUser.filePath),
        validating: String(path.dropFirst(2))
      )
    } else {
      try self.init(validating: path)
    }
  }
}

/// The default directory to write generated files
/// `<TEMPORARY_DIRECTORY>/sourcekit-lsp/`
package var defaultDirectoryForGeneratedFiles: URL {
  URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sourcekit-lsp")
}
