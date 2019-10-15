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

import Foundation

public protocol ToolchainLanguageServerCrashHandler: AnyObject {
  /// Called when the given `ToolchainLanguageServer` has crashed and needs to be reinitialized with information
  /// such as the list of open documents.
  ///
  /// The handler may or may not chose to re-open previously open documents and/or
  /// stop sending any further requests to the given `ToolchainLanguageServer`.
  func handleCrash(_ languageService: ToolchainLanguageServer, _ debugInfo: String)
}
