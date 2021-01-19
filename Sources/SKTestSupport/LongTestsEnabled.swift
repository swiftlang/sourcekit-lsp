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

public var longTestsEnabled: Bool {
  if let value = ProcessInfo.processInfo.environment["SOURCEKIT_LSP_ENABLE_LONG_TESTS"] {
    return value == "1" || value == "YES"
  }
  return false
}
