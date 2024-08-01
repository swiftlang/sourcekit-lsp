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

import Foundation

/// The bundle of the currently executing test.
package let testBundle: Bundle = {
  #if os(macOS)
  if let bundle = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") }) {
    return bundle
  }
  fatalError("couldn't find the test bundle")
  #else
  return Bundle.main
  #endif
}()

/// The path to the built products directory, ie. `.build/debug/arm64-apple-macosx` or the platform-specific equivalent.
package let productsDirectory: URL = {
  #if os(macOS)
  return testBundle.bundleURL.deletingLastPathComponent()
  #else
  return testBundle.bundleURL
  #endif
}()
