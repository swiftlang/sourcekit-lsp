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

import BuildServerProtocol
import SKLogging

extension BuildTargetIdentifier {
  package static let dummy: BuildTargetIdentifier = BuildTargetIdentifier(uri: try! URI(string: "dummy://dummy"))
}

extension BuildTargetIdentifier: CustomLogStringConvertible {
  public var description: String {
    return uri.stringValue
  }

  public var redactedDescription: String {
    return uri.stringValue.hashForLogging
  }
}
