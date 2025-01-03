//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Csourcekitd
import SourceKitD

/// Provide getters to get values for a sourcekitd request array.
///
/// This is not part of the `SourceKitD` module because it uses `SourceKitD.servicePluginAPI` which must not be accessed
/// outside of the service plugin.
final class SKDRequestArrayReader: Sendable {
  nonisolated(unsafe) let array: sourcekitd_api_object_t
  private let sourcekitd: SourceKitD

  /// Creates an `SKDRequestArray` that essentially provides a view into the given opaque `sourcekitd_api_object_t`.
  init(_ array: sourcekitd_api_object_t, sourcekitd: SourceKitD) {
    self.array = array
    self.sourcekitd = sourcekitd
    _ = sourcekitd.api.request_retain(array)
  }

  deinit {
    _ = sourcekitd.api.request_release(array)
  }

  var count: Int { return sourcekitd.servicePluginApi.request_array_get_count(array) }

  /// If the `applier` returns `false`, iteration terminates.
  @discardableResult
  func forEach(_ applier: (Int, SKDRequestDictionaryReader) throws -> Bool) rethrows -> Bool {
    for i in 0..<count {
      let value = sourcekitd.servicePluginApi.request_array_get_value(array, i)!
      guard let dict = SKDRequestDictionaryReader(value, sourcekitd: sourcekitd) else {
        continue
      }
      if try !applier(i, dict) {
        return false
      }
    }
    return true
  }

  /// Attempt to access the item at `index` as a string.
  subscript(index: Int) -> String? {
    if let cstr = sourcekitd.servicePluginApi.request_array_get_string(array, index) {
      return String(cString: cstr)
    }
    return nil
  }

  var asStringArray: [String] {
    var result: [String] = []
    for i in 0..<count {
      if let string = self[i] {
        result.append(string)
      }
    }
    return result
  }
}
