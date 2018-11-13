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

import SPMLibc

public final class DLHandle {
  var rawValue: UnsafeMutableRawPointer? = nil

  init(rawValue: UnsafeMutableRawPointer) {
    self.rawValue = rawValue
  }

  deinit {
    precondition(rawValue == nil, "DLHandle must be closed or explicitly leaked before destroying")
  }

  public func close() throws {
    if let handle = rawValue {
      guard dlclose(handle) == 0 else {
        throw DLError.dlclose(dlerror() ?? "unknown error")
      }
    }
    rawValue = nil
  }

  public func leak() {
    rawValue = nil
  }
}

public struct DLOpenFlags: RawRepresentable, OptionSet {

  public static let lazy: DLOpenFlags = DLOpenFlags(rawValue: RTLD_LAZY)
  public static let now: DLOpenFlags = DLOpenFlags(rawValue: RTLD_NOW)
  public static let local: DLOpenFlags = DLOpenFlags(rawValue: RTLD_LOCAL)
  public static let global: DLOpenFlags = DLOpenFlags(rawValue: RTLD_GLOBAL)

  // Platform-specific flags.
  #if os(macOS)
    public static let first: DLOpenFlags = DLOpenFlags(rawValue: RTLD_FIRST)
  #else
    public static let first: DLOpenFlags = DLOpenFlags(rawValue: 0)
  #endif

  public var rawValue: Int32

  public init(rawValue: Int32) {
    self.rawValue = rawValue
  }
}

public enum DLError: Swift.Error {
  case dlopen(String)
  case dlclose(String)
}

public func dlopen(_ path: String?, mode: DLOpenFlags) throws -> DLHandle {
  guard let handle = SPMLibc.dlopen(path, mode.rawValue) else {
    throw DLError.dlopen(dlerror() ?? "unknown error")
  }
  return DLHandle(rawValue: handle)
}

public func dlsym<T>(_ handle: DLHandle, symbol: String) -> T? {
  guard let ptr = dlsym(handle.rawValue!, symbol) else {
    return nil
  }
  return unsafeBitCast(ptr, to: T.self)
}

public func dlclose(_ handle: DLHandle) throws {
  try handle.close()
}

public func dlerror() -> String? {
  if let err: UnsafeMutablePointer<Int8> = dlerror() {
    return String(cString: err)
  }
  return nil
}
