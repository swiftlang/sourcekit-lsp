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

package import LanguageServerProtocol

extension Array<CompletionItem> {
  /// Remove `sortText` and `data` from all completion items as these are not stable across runs. Instead, sort items
  /// by `sortText` to ensure we test them in the order that an editor would display them in.
  package var clearingUnstableValues: [CompletionItem] {
    return
      self
      .sorted(by: { ($0.sortText ?? "") < ($1.sortText ?? "") })
      .map {
        var item = $0
        item.sortText = nil
        item.data = nil
        return item
      }
  }
}
