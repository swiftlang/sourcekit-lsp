//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A playground item that can be used to identify playgrounds alongside a source file.
public struct PlaygroundItem: ResponseType, Equatable {
  /// Identifier for the `PlaygroundItem`.
  ///
  /// This identifier uniquely identifies the playground. It can be used to run an individual playground with `swift play`.
  public var id: String

  /// Display name describing the playground.
  public var label: String?

  /// The location of the #Playground macro expansion in the source code.
  public var location: Location

  public init(
    id: String,
    label: String?,
    location: Location,
  ) {
    self.id = id
    self.label = label
    self.location = location
  }
}
