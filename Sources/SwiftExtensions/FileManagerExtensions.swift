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
#else
import Foundation
#endif

extension FileManager {
  /// Same as `fileExists(atPath:)` but takes a `URL` instead of a `String`.
  package func fileExists(at url: URL) -> Bool {
    guard let filePath = try? url.filePath else {
      return false
    }
    return self.fileExists(atPath: filePath)
  }
}
