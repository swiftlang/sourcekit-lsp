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

#if compiler(>=6)
package import BuildServerProtocol
import SKLogging
#else
import BuildServerProtocol
import SKLogging
#endif

extension BuildTargetIdentifier {
  package static let dummy: BuildTargetIdentifier = BuildTargetIdentifier(uri: try! URI(string: "dummy://dummy"))
}

#if compiler(>=6)
extension BuildTargetIdentifier: CustomLogStringConvertible {
  package var description: String {
    return uri.stringValue
  }

  package var redactedDescription: String {
    return uri.stringValue.hashForLogging
  }
}
#else
extension BuildTargetIdentifier: CustomLogStringConvertible {
  public var description: String {
    return uri.stringValue
  }

  public var redactedDescription: String {
    return uri.stringValue.hashForLogging
  }
}
#endif
