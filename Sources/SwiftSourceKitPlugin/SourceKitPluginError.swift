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

import SourceKitD

/// An error that can be converted into an `SKDResponse``.
protocol SourceKitPluginError: Swift.Error {
  func response(sourcekitd: SourceKitD) -> SKDResponse
}

struct GenericPluginError: SourceKitPluginError {
  let kind: SKDResponse.ErrorKind
  let description: String

  internal init(kind: SKDResponse.ErrorKind = .failed, description: String) {
    self.kind = kind
    self.description = description
  }

  func response(sourcekitd: SourceKitD) -> SKDResponse {
    return SKDResponse(error: kind, description: description, sourcekitd: sourcekitd)
  }
}
