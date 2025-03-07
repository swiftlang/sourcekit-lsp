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

package import Foundation
import SwiftExtensions

package import struct TSCBasic.AbsolutePath
package import struct TSCBasic.RelativePath

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
