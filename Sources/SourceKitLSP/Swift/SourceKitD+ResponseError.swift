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

import SourceKitD
import LanguageServerProtocol

extension ResponseError {
  public init(_ value: SKDError) {
    switch value {
    case .requestCancelled:
      self = .serverCancelled
    case .requestFailed(let desc):
      self = .unknown("sourcekitd request failed: \(desc)")
    case .requestInvalid(let desc):
      self = .unknown("sourcekitd invalid request \(desc)")
    case .missingRequiredSymbol(let desc):
      self = .unknown("sourcekitd missing required symbol '\(desc)'")
    case .connectionInterrupted:
      self = .unknown("sourcekitd connection interrupted")
    }
  }
}
