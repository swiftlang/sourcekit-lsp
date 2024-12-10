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

import SwiftExtensions

#if compiler(>=6)
package import struct TSCBasic.AbsolutePath
package import struct TSCBasic.RelativePath
package import Foundation
#else
import struct TSCBasic.AbsolutePath
import struct TSCBasic.RelativePath
import Foundation
#endif

extension URL {
  package func appending(_ relativePath: RelativePath) -> URL {
    var result = self
    for component in relativePath.components {
      if component == "." {
        continue
      }
      result.appendPathComponent(component)
    }
    return result
  }
}
