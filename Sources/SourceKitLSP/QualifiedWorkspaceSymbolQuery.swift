//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A `workspace/symbol` query split into its qualified parts.
///
/// For example:
///   `"String.description"`   → `containerChain: ["String"], member: "description"`
///   `"Foo::bar"`             → `containerChain: ["Foo"], member: "bar"`
///   `"Outer.Inner.method"`   → `containerChain: ["Outer", "Inner"], member: "method"`
///   `"Foo."`                 → `containerChain: ["Foo"], member: ""`
///   `"Foo.bar(baz:)"`        → `containerChain: ["Foo"], member: "bar(baz:)"` (a lone `:` is literal)
///
/// An unqualified query (no separator, e.g. `"description"`) fails to parse and returns `nil`.
package struct QualifiedWorkspaceSymbolQuery: Equatable {
  /// Container chain in outer-to-inner order. Always non-empty for a successfully-parsed query.
  package let containerChain: [String]

  /// The trailing component the user is searching for. May be empty (e.g. for the query `Foo.`).
  package let member: String

  /// Parse a `workspace/symbol` query, splitting on the trailing `.` or `::` qualifier separators.
  ///
  /// Returns `nil` if the query has no qualifier or the container chain is empty (so callers can fall
  /// back to the unqualified search path). A trailing separator with an empty member (e.g. `Foo.`)
  /// is a valid qualified query that lists all members of the container.
  package init?(_ query: String) {
    // Split the query into components on the `.` and `::` separators. The last component is the member
    // being searched for; the preceding components are the container chain. A lone `:` is not a separator
    // — it is a literal character, e.g. an argument label in `Collection.append(contentsOf:)`.
    var components =
      query
      .replacing("::", with: ".")
      .split(separator: ".", omittingEmptySubsequences: false)
      .map(String.init)

    // Without a separator the query isn't qualified; callers fall back to the unqualified search path.
    guard components.count >= 2 else { return nil }
    let member = components.removeLast()
    let containerChain = components
    // Container chain segments must be non-empty (rejects leading and doubled separators). An empty
    // member is allowed (e.g. `Foo.` lists all members of the container).
    guard !containerChain.contains(where: \.isEmpty) else { return nil }

    self.containerChain = containerChain
    self.member = member
  }
}

extension String {
  /// Returns `true` if the characters of `subsequence` appear in order within `self`, compared
  /// case-insensitively. An empty `subsequence` always matches.
  package func fuzzilyContains(subsequence: String) -> Bool {
    var remaining = Substring(subsequence.lowercased())
    for character in self.lowercased() where character == remaining.first {
      remaining = remaining.dropFirst()
    }
    return remaining.isEmpty
  }
}
