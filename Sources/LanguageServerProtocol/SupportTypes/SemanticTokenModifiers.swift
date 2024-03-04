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

import Foundation

/// Additional metadata about a token.
///
/// Similar to `SemanticTokenTypes`, the bit indices should
/// be numbered starting at 0.
public struct SemanticTokenModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  public static let declaration = Self(rawValue: 1 << 0)
  public static let definition = Self(rawValue: 1 << 1)
  public static let readonly = Self(rawValue: 1 << 2)
  public static let `static` = Self(rawValue: 1 << 3)
  public static let deprecated = Self(rawValue: 1 << 4)
  public static let abstract = Self(rawValue: 1 << 5)
  public static let async = Self(rawValue: 1 << 6)
  public static let modification = Self(rawValue: 1 << 7)
  public static let documentation = Self(rawValue: 1 << 8)
  public static let defaultLibrary = Self(rawValue: 1 << 9)

  public var name: String? {
    switch self {
    case .declaration: return "declaration"
    case .definition: return "definition"
    case .readonly: return "readonly"
    case .static: return "static"
    case .deprecated: return "deprecated"
    case .abstract: return "abstract"
    case .async: return "async"
    case .modification: return "modification"
    case .documentation: return "documentation"
    case .defaultLibrary: return "defaultLibrary"
    default: return nil
    }
  }

  /// All available modifiers, in ascending order of the bit index
  /// they are represented with (starting at the rightmost bit).
  public static let predefined: [Self] = [
    .declaration,
    .definition,
    .readonly,
    .static,
    .deprecated,
    .abstract,
    .async,
    .modification,
    .documentation,
    .defaultLibrary,
  ]
}
