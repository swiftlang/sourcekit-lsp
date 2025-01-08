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

package enum Platform: Equatable, Sendable {
  case darwin
  case linux
  case windows

  package static var current: Platform? {
    #if os(Windows)
    return .windows
    #elseif canImport(Darwin)
    return .darwin
    #else
    return .linux
    #endif
  }

  /// The file extension used for a dynamic library on this platform.
  package var dynamicLibraryExtension: String {
    switch self {
    case .darwin: return ".dylib"
    case .linux: return ".so"
    case .windows: return ".dll"
    }
  }

  package var executableExtension: String {
    switch self {
    case .windows: return ".exe"
    case .linux, .darwin: return ""
    }
  }
}
