//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A notification that should be used by the client to modify the trace setting of the server.
public struct SetTraceNotification: NotificationType, Hashable, Codable {
  public static let method: String = "$/setTrace"

  /// The new value that should be assigned to the trace setting.
  public var value: Tracing

  public init(value: Tracing) {
    self.value = value
  }
}
