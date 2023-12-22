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

import Csourcekitd
import LSPLogging

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(CRT)
import CRT
#endif

/// Values that can be stored in a `SKDRequestDictionary`.
///
/// - Warning: `SKDRequestDictionary.subscript` and `SKDRequestArray.append`
///   switch exhaustively over this protocol.
///   Do not add new conformances without adding a new case in the subscript and
///   `append` function.
public protocol SKDValue {}

extension String: SKDValue {}
extension Int: SKDValue {}
extension sourcekitd_uid_t: SKDValue {}
extension SKDRequestDictionary: SKDValue {}
extension SKDRequestArray: SKDValue {}
extension Array<SKDValue>: SKDValue {}
extension Dictionary<sourcekitd_uid_t, SKDValue>: SKDValue {}
extension Optional: SKDValue where Wrapped: SKDValue {}

extension Dictionary<sourcekitd_uid_t, SKDValue> {
  /// Create an `SKDRequestDictionary` from this dictionary.
  ///
  /// If a value is `nil`, the corresponding key will not be added
  public func skd(_ sourcekitd: SourceKitD) -> SKDRequestDictionary {
    let result = SKDRequestDictionary(sourcekitd: sourcekitd)
    for (key, value) in self {
      result.set(key, to: value)
    }
    return result
  }
}

public final class SKDRequestDictionary {
  public let dict: sourcekitd_object_t?
  public let sourcekitd: SourceKitD

  public init(_ dict: sourcekitd_object_t? = nil, sourcekitd: SourceKitD) {
    self.dict = dict ?? sourcekitd.api.request_dictionary_create(nil, nil, 0)
    self.sourcekitd = sourcekitd
  }

  deinit {
    sourcekitd.api.request_release(dict)
  }

  public func set(_ key: sourcekitd_uid_t, to newValue: SKDValue) {
    switch newValue {
    case let newValue as String:
      sourcekitd.api.request_dictionary_set_string(dict, key, newValue)
    case let newValue as Int:
      sourcekitd.api.request_dictionary_set_int64(dict, key, Int64(newValue))
    case let newValue as sourcekitd_uid_t:
      sourcekitd.api.request_dictionary_set_uid(dict, key, newValue)
    case let newValue as SKDRequestDictionary:
      sourcekitd.api.request_dictionary_set_value(dict, key, newValue.dict)
    case let newValue as SKDRequestArray:
      sourcekitd.api.request_dictionary_set_value(dict, key, newValue.array)
    case let newValue as Array<SKDValue>:
      self.set(key, to: newValue.skd(sourcekitd))
    case let newValue as Dictionary<sourcekitd_uid_t, SKDValue>:
      self.set(key, to: newValue.skd(sourcekitd))
    case let newValue as Optional<SKDValue>:
      if let newValue {
        self.set(key, to: newValue)
      }
    default:
      preconditionFailure("Unknown type conforming to SKDValueProtocol")
    }
  }
}

extension SKDRequestDictionary: CustomStringConvertible {
  public var description: String {
    let ptr = sourcekitd.api.request_description_copy(dict)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}

extension SKDRequestDictionary: CustomLogStringConvertible {
  public var redactedDescription: String {
    // FIXME: (logging) Implement a better redacted log that contains keys,
    // number of elements in an array but not the data itself.
    return "<\(description.filter(\.isNewline).count) lines>"
  }
}
