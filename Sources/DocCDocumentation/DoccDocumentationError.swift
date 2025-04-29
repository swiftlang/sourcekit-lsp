//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
package import LanguageServerProtocol

package enum DocCDocumentationError: LocalizedError {
  case noDocumentation
  case indexNotAvailable
  case symbolNotFound(String)

  var errorDescription: String? {
    switch self {
    case .noDocumentation:
      return "No documentation could be rendered for the position in this document"
    case .indexNotAvailable:
      return "The index is not availble to complete the request"
    case .symbolNotFound(let symbolName):
      return "Could not find symbol \(symbolName) in the project"
    }
  }
}

package extension ResponseError {
  static func requestFailed(doccDocumentationError: DocCDocumentationError) -> ResponseError {
    return ResponseError.requestFailed(doccDocumentationError.localizedDescription)
  }
}
