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

import LanguageServerProtocol

public typealias OriginId = String

public struct PrepareTargetsRequest: RequestType, Hashable {
  public static let method: String = "buildTarget/prepare"
  public typealias Response = VoidResponse

  /// A list of build targets to prepare.
  public var targets: [BuildTargetIdentifier]

  public var originId: OriginId?

  public init(targets: [BuildTargetIdentifier], originId: OriginId? = nil) {
    self.targets = targets
    self.originId = originId
  }
}
