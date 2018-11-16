//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public enum DocumentHighlightKind: Int, Codable, Hashable {
  case text = 1
  case read = 2
  case write = 3
}

public struct DocumentHighlight: ResponseType, Hashable {

  /// The location of the highlight.
  public var range: Range<Position>

  /// What kind of reference this is. Default is `.text`.
  public var kind: DocumentHighlightKind?

  public init(range: Range<Position>, kind: DocumentHighlightKind?) {
    self.range = range
    self.kind = kind
  }
}
