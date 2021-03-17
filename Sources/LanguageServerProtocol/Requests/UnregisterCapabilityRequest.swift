//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request sent from the server to the client to unregister a previously registered
/// capability.
public struct UnregisterCapabilityRequest: RequestType, Hashable {
  public static let method: String = "client/unregisterCapability"
  public typealias Response = VoidResponse

  /// Capabilities to unregister.
  public var unregistrations: [Unregistration]

  public init(unregistrations: [Unregistration]) {
    self.unregistrations = unregistrations
  }
}

extension UnregisterCapabilityRequest: Codable {
  private enum CodingKeys: String, CodingKey {
    /// This should correctly be named `unregistrations`. However changing this
    /// is a breaking change and needs to wait until the 4.x LSP spec update.
    case unregistrations = "unregisterations"
  }
}

/// General parameters to unregister a capability.
public struct Unregistration: Codable, Hashable {
  /// The id used to unregister the capability, usually provided through the
  /// register request.
  public var id: String

  /// The method/capability to unregister for.
  public var method: String

  public init(id: String, method: String) {
    self.id = id
    self.method = method
  }
}
