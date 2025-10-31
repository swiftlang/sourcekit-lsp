//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request indicating the server should start shutting down.
///
/// The server should cleanup any state that it needs to, but not exit (otherwise the response might
/// not reach the client). See `Exit`.
///
/// - Returns: Void.
public struct ShutdownRequest: LSPRequest, Hashable {
  public static let method: String = "shutdown"

  public struct Response: ResponseType, Equatable {
    public init() {}

    public init(from decoder: any Decoder) throws {}

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    }
  }

  public init() {}
}
