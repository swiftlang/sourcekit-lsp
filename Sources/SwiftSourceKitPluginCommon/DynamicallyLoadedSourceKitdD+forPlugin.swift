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

import Foundation
import SKLogging
import SwiftExtensions

#if compiler(>=6)
package import SourceKitD
#else
import SourceKitD
#endif

extension DynamicallyLoadedSourceKitD {
  private static nonisolated(unsafe) var _forPlugin: SourceKitD?
  package static var forPlugin: SourceKitD {
    get {
      guard let _forPlugin else {
        fatalError("forPlugin must only be accessed after it was set in sourcekitd_plugin_initialize_2")
      }
      return _forPlugin
    }
    set {
      precondition(_forPlugin == nil, "DynamicallyLoadedSourceKitD.forPlugin must not be set twice")
      _forPlugin = newValue
    }
  }
}
