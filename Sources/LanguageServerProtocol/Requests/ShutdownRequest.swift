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
public struct ShutdownRequest: RequestType, Hashable {
  public static let method: String = "shutdown"
  public typealias Response = VoidResponse

  public init() { }
}

@available(*, deprecated, renamed: "ShutdownRequest")
public typealias Shutdown = ShutdownRequest
