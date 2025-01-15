//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

package struct Flair: OptionSet {
  package var rawValue: Int64

  package init(rawValue: Int64) {
    self.rawValue = rawValue
  }

  package init(_ rawValue: Int64) {
    self.rawValue = rawValue
  }

  /// Xcode prior to version 13, grouped many high priority completions under the tag 'expression specific'.
  /// To aid in mapping those into the new API, redefine this case as a catch-all 'high priority' expression.
  /// Please do not use it for new cases, instead, add a case to this enum to model the significance of the completion.
  package static let oldExpressionSpecific_pleaseAddSpecificCaseToThisEnum = Flair(1 << 0)

  /// E.g. `override func foo() { super.foo() ...`
  package static let chainedCallToSuper = Flair(1 << 1)

  /// E.g. `bar.baz` in `foo.bar.baz`.
  package static let chainedMember = Flair(1 << 2)

  /// E.g. using class, struct, protocol, public, private, or fileprivate at file level.
  internal static let _situationallyLikely = Flair(1 << 3)

  /// E.g. using `class` inside of a function body, or a protocol in an expression.
  internal static let _situationallyUnlikely = Flair(1 << 4)

  /// E.g. referencing a type at top level position in a non script/main.swift file.
  internal static let _situationallyInvalid = Flair(1 << 5)

  /// E.g. an instance method/property in SwiftUI ViewBuilder with implicit-self context.
  package static let swiftUIModifierOnSelfWhileBuildingSelf = Flair(1 << 6)

  /// E.g. `frame()`, since you almost certainly want to pass an argument to it.
  package static let swiftUIUnlikelyViewMember = Flair(1 << 7)

  /// E.g. using struct, enum, protocol, class, public, private, or fileprivate at file level.
  package static let commonKeywordAtCurrentPosition = Flair(1 << 8)

  /// E.g. nesting class in a function.
  package static let rareKeywordAtCurrentPosition = Flair(1 << 9)

  /// E.g. using a protocol by name in an expression in a non-type position. `let x = 3 + Comparable…`
  package static let rareTypeAtCurrentPosition = Flair(1 << 10)

  /// E.g. referencing a type, function, etc… at top level position in a non script/main.swift file.
  package static let expressionAtNonScriptOrMainFileScope = Flair(1 << 11)

  /// E.g. `printContents`, which is almost never what you want when typing `print`.
  package static let rareMemberWithCommonName = Flair(1 << 12)

  @available(
    *,
    deprecated,
    message: """
        This is an escape hatch for scenarios we haven't thought of. \
        When using, file a bug report to name the new situational oddity so that we can directly model it.
      """
  )
  package static let situationallyLikely = _situationallyLikely

  @available(
    *,
    deprecated,
    message: """
        This is an escape hatch for scenarios we haven't thought of. \
        When using, file a bug report to name the new situational oddity so that we can directly model it.
      """
  )
  package static let situationallyUnlikely = _situationallyUnlikely

  @available(
    *,
    deprecated,
    message: """
        This is an escape hatch for scenarios we haven't thought of. \
        When using, file a bug report to name the new situational oddity so that we can directly model it.
      """
  )
  package static let situationallyInvalid = _situationallyInvalid
}

extension Flair: CustomDebugStringConvertible {
  private static let namedValues: [(Flair, String)] = [
    (
      .oldExpressionSpecific_pleaseAddSpecificCaseToThisEnum,
      "oldExpressionSpecific_pleaseAddSpecificCaseToThisEnum"
    ),
    (.chainedCallToSuper, "chainedCallToSuper"),
    (.chainedMember, "chainedMember"),
    (._situationallyLikely, "_situationallyLikely"),
    (._situationallyUnlikely, "_situationallyUnlikely"),
    (._situationallyInvalid, "_situationallyInvalid"),
    (.swiftUIModifierOnSelfWhileBuildingSelf, "swiftUIModifierOnSelfWhileBuildingSelf"),
    (.swiftUIUnlikelyViewMember, "swiftUIUnlikelyViewMember"),
    (.commonKeywordAtCurrentPosition, "commonKeywordAtCurrentPosition"),
    (.rareKeywordAtCurrentPosition, "rareKeywordAtCurrentPosition"),
    (.rareTypeAtCurrentPosition, "rareTypeAtCurrentPosition"),
    (.expressionAtNonScriptOrMainFileScope, "expressionAtNonScriptOrMainFileScope"),
    (.rareMemberWithCommonName, "rareMemberWithCommonName"),
  ]

  package var debugDescription: String {
    var descriptions = [String]()
    for (flair, name) in Self.namedValues {
      if self.contains(flair) {
        descriptions.append(name)
      }
    }
    if descriptions.isEmpty {
      return "none"
    } else {
      return descriptions.joined(separator: ",")
    }
  }
}

extension Flair: OptionSetBinaryCodable {}

extension Flair {
  package var factor: Double {
    return self.scoreComponent
  }
}
