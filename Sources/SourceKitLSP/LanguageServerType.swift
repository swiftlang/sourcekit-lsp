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

import IndexStoreDB

/// Exhaustive enumeration of all toolchain language servers known to SourceKit-LSP.
enum LanguageServerType: Hashable {
  case clangd
  case swift

  init?(language: Language) {
    switch language {
    case .c, .cpp, .objective_c, .objective_cpp:
      self = .clangd
    case .swift:
      self = .swift
    default:
      return nil
    }
  }

  init?(symbolProvider: SymbolProviderKind?) {
    switch symbolProvider {
    case .clang: self = .clangd
    case .swift: self = .swift
    case nil: return nil
    }
  }

  /// The `LanguageService` class used to provide functionality for this language class.
  var serverType: LanguageService.Type {
    switch self {
    case .clangd:
      return ClangLanguageService.self
    case .swift:
      return SwiftLanguageService.self
    }
  }
}
