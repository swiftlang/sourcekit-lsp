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

import Csourcekitd

struct OpaqueIDEInspectionInstance: Sendable {
  nonisolated(unsafe) let value: UnsafeMutableRawPointer

  internal init?(_ value: UnsafeMutableRawPointer?) {
    guard let value else {
      return nil
    }
    self.value = value
  }
}

struct RequestHandle: Sendable {
  nonisolated(unsafe) let handle: sourcekitd_api_request_handle_t
  internal init?(_ handle: sourcekitd_api_request_handle_t?) {
    guard let handle else {
      return nil
    }
    self.handle = handle
  }

  var numericValue: Int {
    Int(bitPattern: handle)
  }
}
