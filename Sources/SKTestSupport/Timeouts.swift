//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import Foundation

/// The default duration how long tests should wait for responses from
/// SourceKit-LSP / sourcekitd / clangd.
package let defaultTimeout: TimeInterval = {
  if let customTimeoutStr = ProcessInfo.processInfo.environment["SOURCEKIT_LSP_TEST_TIMEOUT"],
    let customTimeout = TimeInterval(customTimeoutStr)
  {
    return customTimeout
  }
  return 180
}()

package var defaultTimeoutDuration: Duration { .seconds(defaultTimeout) }
