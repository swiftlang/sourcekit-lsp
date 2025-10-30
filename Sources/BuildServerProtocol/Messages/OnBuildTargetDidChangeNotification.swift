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

public import LanguageServerProtocol

/// The build target changed notification is sent from the server to the client
/// to signal a change in a build target. The server communicates during the
/// initialize handshake whether this method is supported or not.
public struct OnBuildTargetDidChangeNotification: BSPNotification, Equatable {
  public static let method: String = "buildTarget/didChange"

  /// **(BSP Extension)**
  /// `changes` can be `nil` to indicate that all targets might have changed.
  public var changes: [BuildTargetEvent]?

  public init(changes: [BuildTargetEvent]?) {
    self.changes = changes
  }
}

public struct BuildTargetEvent: Codable, Hashable, Sendable {
  /// The identifier for the changed build target.
  public var target: BuildTargetIdentifier

  /// The kind of change for this build target.
  public var kind: BuildTargetEventKind?

  /// Kind of data to expect in the `data` field. If this field is not set, the kind of data is not specified.
  public var dataKind: BuildTargetEventDataKind?

  /// Any additional metadata about what information changed.
  public var data: LSPAny?

  public init(
    target: BuildTargetIdentifier,
    kind: BuildTargetEventKind?,
    dataKind: BuildTargetEventDataKind?,
    data: LSPAny?
  ) {
    self.target = target
    self.kind = kind
    self.dataKind = dataKind
    self.data = data
  }
}

public enum BuildTargetEventKind: Int, Codable, Hashable, Sendable {
  /// The build target is new.
  case created = 1

  /// The build target has changed.
  case changed = 2

  /// The build target has been deleted.
  case deleted = 3
}

public struct BuildTargetEventDataKind: RawRepresentable, Codable, Hashable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}
