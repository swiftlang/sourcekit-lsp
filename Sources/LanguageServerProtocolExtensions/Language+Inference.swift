//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if compiler(>=6)
import Foundation
package import LanguageServerProtocol
#else
import Foundation
import LanguageServerProtocol
#endif

extension Language {
  package enum SemanticKind {
    case clang
    case swift
  }

  package var semanticKind: SemanticKind? {
    switch self {
    case .swift:
      return .swift
    case .c, .cpp, .objective_c, .objective_cpp:
      return .clang
    default:
      return nil
    }
  }

  package init?(inferredFromFileExtension uri: DocumentURI) {
    // URL.pathExtension is only set for file URLs but we want to also infer a file extension for non-file URLs like
    // untitled:file.cpp
    let pathExtension = uri.fileURL?.pathExtension ?? (uri.pseudoPath as NSString).pathExtension
    switch pathExtension {
    case "c": self = .c
    case "cpp", "cc", "cxx", "hpp": self = .cpp
    case "m": self = .objective_c
    case "mm", "h": self = .objective_cpp
    case "swift": self = .swift
    default: return nil
    }
  }
}
