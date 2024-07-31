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

import Foundation

extension FileManager {
  /// Same as `homeDirectoryForCurrentUser` but works around
  /// https://github.com/apple/swift-corelibs-foundation/issues/5041, which causes a null byte
  package var sanitizedHomeDirectoryForCurrentUser: URL {
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    #if os(Windows)
    if homeDirectory.lastPathComponent.hasSuffix("\0") {
      let newLastPathComponent = String(homeDirectory.lastPathComponent.dropLast())
      return homeDirectory.deletingLastPathComponent().appendingPathComponent(newLastPathComponent)
    }
    #endif
    return homeDirectory
  }
}
