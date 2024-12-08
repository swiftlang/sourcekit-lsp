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

extension URL {
  var doccCatalogURL: URL? {
    var pathComponents = self.pathComponents
    var result = self
    while let lastPathComponent = pathComponents.last {
      if lastPathComponent.hasSuffix(".docc") {
        return result
      }
      pathComponents.removeLast()
      result.deleteLastPathComponent()
    }
    return nil
  }
}