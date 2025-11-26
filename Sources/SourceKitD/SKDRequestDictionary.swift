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

package import Csourcekitd
@_spi(SourceKitLSP) import SKLogging

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#elseif canImport(Bionic)
import Bionic
#endif

/// Values that can be stored in a `SKDRequestDictionary`.
///
/// - Warning: `SKDRequestDictionary.subscript` and `SKDRequestArray.append`
///   switch exhaustively over this protocol.
///   Do not add new conformances without adding a new case in the subscript and
///   `append` function.
package protocol SKDRequestValue {}

extension String: SKDRequestValue {}
extension Int: SKDRequestValue {}
extension sourcekitd_api_uid_t: SKDRequestValue {}
extension SKDRequestDictionary: SKDRequestValue {}
extension SKDRequestArray: SKDRequestValue {}
extension [SKDRequestValue]: SKDRequestValue {}
extension [sourcekitd_api_uid_t: SKDRequestValue]: SKDRequestValue {}
extension Optional: SKDRequestValue where Wrapped: SKDRequestValue {}

extension SourceKitD {
  /// Create a `SKDRequestDictionary` from the given dictionary.
  nonisolated package func dictionary(_ dict: [sourcekitd_api_uid_t: any SKDRequestValue]) -> SKDRequestDictionary {
    let result = SKDRequestDictionary(sourcekitd: self)
    for (key, value) in dict {
      result.set(key, to: value)
    }
    return result
  }
}

package final class SKDRequestDictionary: Sendable {
  nonisolated(unsafe) let dict: sourcekitd_api_object_t
  private let sourcekitd: SourceKitD

  package init(_ dict: sourcekitd_api_object_t? = nil, sourcekitd: SourceKitD) {
    self.dict = dict ?? sourcekitd.api.request_dictionary_create(nil, nil, 0)!
    self.sourcekitd = sourcekitd
  }

  deinit {
    sourcekitd.api.request_release(dict)
  }

  package func set(_ key: sourcekitd_api_uid_t, to newValue: any SKDRequestValue) {
    switch newValue {
    case let newValue as String:
      sourcekitd.api.request_dictionary_set_string(dict, key, newValue)
    case let newValue as Int:
      sourcekitd.api.request_dictionary_set_int64(dict, key, Int64(newValue))
    case let newValue as sourcekitd_api_uid_t:
      sourcekitd.api.request_dictionary_set_uid(dict, key, newValue)
    case let newValue as SKDRequestDictionary:
      sourcekitd.api.request_dictionary_set_value(dict, key, newValue.dict)
    case let newValue as SKDRequestArray:
      sourcekitd.api.request_dictionary_set_value(dict, key, newValue.array)
    case let newValue as [any SKDRequestValue]:
      self.set(key, to: sourcekitd.array(newValue))
    case let newValue as [sourcekitd_api_uid_t: any SKDRequestValue]:
      self.set(key, to: sourcekitd.dictionary(newValue))
    case let newValue as (any SKDRequestValue)?:
      if let newValue {
        self.set(key, to: newValue)
      }
    default:
      preconditionFailure("Unknown type conforming to SKDRequestValue")
    }
  }
}

extension SKDRequestDictionary: CustomStringConvertible {
  package var description: String {
    let ptr = sourcekitd.api.request_description_copy(dict)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}

extension SKDRequestDictionary: CustomLogStringConvertible {
  package var redactedDescription: String {
    // TODO: Implement a better redacted log that contains keys, number of
    // elements in an array but not the data itself.
    // (https://github.com/swiftlang/sourcekit-lsp/issues/1598)
    return "<\(description.filter(\.isNewline).count) lines>"
  }
}
