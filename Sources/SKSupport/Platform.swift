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

import TSCUtility

extension Platform {

  /// The file extension used for a dynamic library on this platform.
  public var dynamicLibraryExtension: String {
    switch self {
    case .darwin: return ".dylib"
    case .linux, .android: return ".so"
    case .windows: return ".dll"
    }
  }

  public var executableExtension: String {
    switch self {
    case .windows: return ".exe"
    case .linux, .android, .darwin: return ""
    }
  }
}
