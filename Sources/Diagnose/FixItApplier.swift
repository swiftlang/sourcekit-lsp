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

import SwiftSyntax

/// Copy of `FixItApplier` in `_SwiftSyntaxTestSupport`.
/// We should use the copy from swift-syntax once it's available as public API.
public enum FixItApplier {
  /// Apply the given edits to the syntax tree.
  ///
  /// - Parameters:
  ///   - edits: The edits to apply to the syntax tree
  ///   - tree: he syntax tree to which the edits should be applied.
  /// - Returns: A `String` representation of the modified syntax tree after applying the edits.
  public static func apply(
    edits: [SourceEdit],
    to tree: any SyntaxProtocol
  ) -> String {
    var edits = edits
    var source = tree.description

    while let edit = edits.first {
      edits = Array(edits.dropFirst())

      let startIndex = source.utf8.index(source.utf8.startIndex, offsetBy: edit.startUtf8Offset)
      let endIndex = source.utf8.index(source.utf8.startIndex, offsetBy: edit.endUtf8Offset)

      source.replaceSubrange(startIndex..<endIndex, with: edit.replacement)

      edits = edits.compactMap { remainingEdit -> SourceEdit? in
        if remainingEdit.replacementRange.overlaps(edit.replacementRange) {
          // The edit overlaps with the previous edit. We can't apply both
          // without conflicts. Apply the one that's listed first and drop the
          // later edit.
          return nil
        }

        // If the remaining edit starts after or at the end of the edit that we just applied,
        // shift it by the current edit's difference in length.
        if edit.endUtf8Offset <= remainingEdit.startUtf8Offset {
          let startPosition = AbsolutePosition(
            utf8Offset: remainingEdit.startUtf8Offset - edit.replacementRange.count + edit.replacementLength
          )
          let endPosition = AbsolutePosition(
            utf8Offset: remainingEdit.endUtf8Offset - edit.replacementRange.count + edit.replacementLength
          )
          return SourceEdit(range: startPosition..<endPosition, replacement: remainingEdit.replacement)
        }

        return remainingEdit
      }
    }

    return source
  }
}

private extension SourceEdit {
  var startUtf8Offset: Int {
    return range.lowerBound.utf8Offset
  }

  var endUtf8Offset: Int {
    return range.upperBound.utf8Offset
  }

  var replacementLength: Int {
    return replacement.utf8.count
  }

  var replacementRange: Range<Int> {
    return startUtf8Offset..<endUtf8Offset
  }
}
