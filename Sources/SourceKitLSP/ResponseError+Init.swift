//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SourceKitD

extension ResponseError {
  package init(_ error: some Error) {
    switch error {
    case let error as ResponseError:
      self = error
    case let error as SKDError:
      self.init(error)
    case is CancellationError:
      self = .cancelled
    default:
      self = .unknown("Unknown error: \(error)")
    }
  }
}
