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

import SwiftExtensions

#if os(Windows)
import CRT
import WinSDK
#elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

package final class DLHandle: Sendable {
  #if os(Windows)
  struct Handle: @unchecked Sendable {
    let handle: HMODULE
  }
  #else
  struct Handle: @unchecked Sendable {
    let handle: UnsafeMutableRawPointer
  }
  #endif
  let rawValue: ThreadSafeBox<Handle?>

  init(rawValue: Handle) {
    self.rawValue = .init(initialValue: rawValue)
  }

  deinit {
    precondition(rawValue.value == nil, "DLHandle must be closed or explicitly leaked before destroying")
  }

  /// The handle must not be used anymore after calling `close`.
  package func close() throws {
    try rawValue.withLock { rawValue in
      if let handle = rawValue {
        #if os(Windows)
        guard FreeLibrary(handle.handle) else {
          throw DLError.close("Failed to FreeLibrary: \(GetLastError())")
        }
        #else
        guard dlclose(handle.handle) == 0 else {
          throw DLError.close(dlerror() ?? "unknown error")
        }
        #endif
      }
      rawValue = nil
    }
  }

  /// The handle must not be used anymore after calling `leak`.
  package func leak() {
    rawValue.value = nil
  }
}

package struct DLOpenFlags: RawRepresentable, OptionSet, Sendable {

  #if !os(Windows)
  package static let lazy: DLOpenFlags = DLOpenFlags(rawValue: RTLD_LAZY)
  package static let now: DLOpenFlags = DLOpenFlags(rawValue: RTLD_NOW)
  package static let local: DLOpenFlags = DLOpenFlags(rawValue: RTLD_LOCAL)
  package static let global: DLOpenFlags = DLOpenFlags(rawValue: RTLD_GLOBAL)

  // Platform-specific flags.
  #if os(macOS)
  package static let first: DLOpenFlags = DLOpenFlags(rawValue: RTLD_FIRST)
  #else
  package static let first: DLOpenFlags = DLOpenFlags(rawValue: 0)
  #endif
  #endif

  package var rawValue: Int32

  package init(rawValue: Int32) {
    self.rawValue = rawValue
  }
}

package enum DLError: Swift.Error {
  case `open`(String)
  case close(String)
}

package func dlopen(_ path: String?, mode: DLOpenFlags) throws -> DLHandle {
  #if os(Windows)
  guard let handle = path?.withCString(encodedAs: UTF16.self, LoadLibraryW) else {
    throw DLError.open("LoadLibraryW failed: \(GetLastError())")
  }
  #else
  guard let handle = dlopen(path, mode.rawValue) else {
    throw DLError.open(dlerror() ?? "unknown error")
  }
  #endif
  return DLHandle(rawValue: DLHandle.Handle(handle: handle))
}

package func dlsym<T>(_ handle: DLHandle, symbol: String) -> T? {
  #if os(Windows)
  guard let ptr = GetProcAddress(handle.rawValue.value!.handle, symbol) else {
    return nil
  }
  #else
  guard let ptr = dlsym(handle.rawValue.value!.handle, symbol) else {
    return nil
  }
  #endif
  return unsafeBitCast(ptr, to: T.self)
}

package func dlclose(_ handle: DLHandle) throws {
  try handle.close()
}

#if !os(Windows)
package func dlerror() -> String? {
  if let err: UnsafeMutablePointer<Int8> = dlerror() {
    return String(cString: err)
  }
  return nil
}
#endif
