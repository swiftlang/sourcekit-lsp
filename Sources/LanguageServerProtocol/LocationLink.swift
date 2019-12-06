//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct LocationLink: Codable, Hashable {
  /// Span of the origin of this link.
  ///
  /// Used as the underlined span for mouse interaction. Defaults to the word range at the mouse position.
  @CustomCodable<PositionRange?>
  public var originSelectionRange: Range<Position>?
  
  /// The target resource identifier of this link.
  public var targetUri: DocumentURI
  
  /// The full target range of this link. If the target for example is a symbol then target range is the
  /// range enclosing this symbol not including leading/trailing whitespace but everything else
  /// like comments. This information is typically used to highlight the range in the editor.
  @CustomCodable<PositionRange>
  public var targetRange: Range<Position>
  
  /// The range that should be selected and revealed when this link is being followed, e.g the name of a function.
  /// Must be contained by the the `targetRange`. See also `DocumentSymbol#range`
  @CustomCodable<PositionRange>
  public var targetSelectionRange: Range<Position>
  
  public init(originSelectionRange: Range<Position>? = nil,
              targetUri: DocumentURI,
              targetRange: Range<Position>,
              targetSelectionRange: Range<Position>) {
    self._originSelectionRange = CustomCodable<PositionRange?>(wrappedValue: originSelectionRange)
    self.targetUri = targetUri
    self._targetRange = CustomCodable<PositionRange>(wrappedValue: targetRange)
    self._targetSelectionRange = CustomCodable<PositionRange>(wrappedValue: targetSelectionRange)
  }
}
