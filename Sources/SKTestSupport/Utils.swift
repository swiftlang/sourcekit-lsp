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

import Foundation
import LanguageServerProtocol

extension Language {
  var fileExtension: String {
    switch self {
    case .objective_c: return "m"
    default: return self.rawValue
    }
  }

  init?(fileExtension: String) {
    switch fileExtension {
    case "m": self = .objective_c
    default: self.init(rawValue: fileExtension)
    }
  }
}

extension DocumentURI {
  /// Create a unique URI for a document of the given language.
  public static func `for`(_ language: Language, testName: String = #function) -> DocumentURI {
    let testBaseName = testName.prefix(while: \.isLetter)

    #if os(Windows)
    let url = URL(fileURLWithPath: "C:/\(testBaseName)/\(UUID())/test.\(language.fileExtension)")
    #else
    let url = URL(fileURLWithPath: "/\(testBaseName)/\(UUID())/test.\(language.fileExtension)")
    #endif
    return DocumentURI(url)
  }
}
