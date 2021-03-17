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

/// An event describing a file change.
public struct FileEvent: Codable, Hashable {
  public var uri: DocumentURI
  public var type: FileChangeType

  public init(uri: DocumentURI, type: FileChangeType) {
    self.uri = uri
    self.type = type
  }
}
/// The type of file event.
///
/// In LSP, this is an integer, so we don't use a closed set.
public struct FileChangeType: RawRepresentable, Codable, Hashable {
  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// The file was created.
  public static let created: FileChangeType = FileChangeType(rawValue: 1)
  /// The file was changed.
  public static let changed: FileChangeType = FileChangeType(rawValue: 2)
  /// The file was deleted.
  public static let deleted: FileChangeType = FileChangeType(rawValue: 3)
}
