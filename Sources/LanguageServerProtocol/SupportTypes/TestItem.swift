//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct TestTag: Codable, Equatable, Sendable {
  /// ID of the test tag. `TestTag` instances with the same ID are considered to be identical.
  public var id: String

  public init(id: String) {
    self.id = id
  }
}

/// A test item that can be shown an a client's test explorer or used to identify tests alongside a source file.
///
/// A `TestItem` can represent either a test suite or a test itself, since they both have similar capabilities.
public struct TestItem: ResponseType, Equatable {
  /// Identifier for the `TestItem`.
  ///
  /// This identifier uniquely identifies the test case or test suite. It can be used to run an individual test (suite).
  public var id: String

  /// Display name describing the test.
  public var label: String

  /// Optional description that appears next to the label.
  public var description: String?

  /// A string that should be used when comparing this item with other items.
  ///
  /// When `nil` the `label` is used.
  public var sortText: String?

  /// Whether the test is disabled.
  public var disabled: Bool

  /// The type of test, eg. the testing framework that was used to declare the test.
  public var style: String

  /// The location of the test item in the source code.
  public var location: Location

  /// The children of this test item.
  ///
  /// For a test suite, this may contain the individual test cases or nested suites.
  public var children: [TestItem]

  /// Tags associated with this test item.
  public var tags: [TestTag]

  public init(
    id: String,
    label: String,
    description: String? = nil,
    sortText: String? = nil,
    disabled: Bool,
    style: String,
    location: Location,
    children: [TestItem],
    tags: [TestTag]
  ) {
    self.id = id
    self.label = label
    self.description = description
    self.sortText = sortText
    self.disabled = disabled
    self.style = style
    self.location = location
    self.children = children
    self.tags = tags
  }
}
