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

@_spi(SourceKitLSP) import LanguageServerProtocol

/// Command to show the Objective-C selector of a method that is exposed to Objective-C.
package struct ShowObjCSelectorCommand: SwiftCommand {
  package static let identifier: String = "show.objc.selector.command"

  package var title = "Show Objective-C Selector"

  /// The selector to show, computed when the code action is created.
  package var selector: String

  init(selector: String) {
    self.selector = selector
  }
}
