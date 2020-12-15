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
#if canImport(Glibc)
import Glibc
#endif

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

  public subscript(key: sourcekitd_uid_t?) -> String {
    get { fatalError("request is set-only") }
    set { sourcekitd.api.request_dictionary_set_string(dict, key, newValue) }
  }
  public subscript(key: sourcekitd_uid_t?) -> Int {
    get { fatalError("request is set-only") }
    set { sourcekitd.api.request_dictionary_set_int64(dict, key, Int64(newValue)) }
  }
  public subscript(key: sourcekitd_uid_t?) -> sourcekitd_uid_t? {
    get { fatalError("request is set-only") }
    set { sourcekitd.api.request_dictionary_set_uid(dict, key, newValue) }
  }
  public subscript(key: sourcekitd_uid_t?) -> SKDRequestDictionary {
    get { fatalError("request is set-only") }
    set { sourcekitd.api.request_dictionary_set_value(dict, key, newValue.dict) }
  }
  public subscript<S>(key: sourcekitd_uid_t?) -> S where S: Sequence, S.Element == String {
    get { fatalError("request is set-only") }
    set {
      let array = SKDRequestArray(sourcekitd: sourcekitd)
      newValue.forEach { array.append($0) }
      sourcekitd.api.request_dictionary_set_value(dict, key, array.array)
    }
  }
  public subscript(key: sourcekitd_uid_t?) -> SKDRequestArray {
    get { fatalError("request is set-only") }
    set { sourcekitd.api.request_dictionary_set_value(dict, key, newValue.array) }
  }
}

extension SKDRequestDictionary: CustomStringConvertible {
  public var description: String {
    let ptr = sourcekitd.api.request_description_copy(dict)!
    defer { free(ptr) }
    return String(cString: ptr)
  }
}
