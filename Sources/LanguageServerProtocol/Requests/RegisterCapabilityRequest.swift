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

import Foundation

/// Request sent from the server to the client to dynamically register for a new capability on the
/// client side.
///
/// Note that not all clients support dynamic registration and clients may provide dynamic
/// registration support for some capabilities but not others.
///
/// Servers must not register the same capability both statically through the initialization result
/// and dynamically. Servers that want to support both should check the client capabilities and only
/// register the capability statically if the client doesn't support dynamic registration for that
/// capability.
public struct RegisterCapabilityRequest: RequestType, Hashable {
  public static let method: String = "client/registerCapability"
  public typealias Response = VoidResponse

  /// Capability registrations.
  public var registrations: [Registration]

  public init(registrations: [Registration]) {
    self.registrations = registrations
  }
}

/// General parameters to register a capability.
public struct Registration: Codable, Hashable {
  /// The id used to register the capability which may be used to unregister support.
  public var id: String

  /// The method/capability to register for.
  public var method: String

  /// Options necessary for this registration.
  public var registerOptions: LSPAny?

  public init(id: String, method: String, registerOptions: LSPAny?) {
    self.id = id
    self.method = method
    self.registerOptions = registerOptions
  }

  /// Create a new `Registration` with a randomly generated id. Save the generated
  /// id if you wish to unregister the given registration.
  public init(method: String, registerOptions: LSPAny?) {
    self.id = UUID().uuidString
    self.method = method
    self.registerOptions = registerOptions
  }
}
