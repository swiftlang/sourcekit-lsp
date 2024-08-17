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

import ArgumentParser

package struct DebugCommand: ParsableCommand {
  package static let configuration = CommandConfiguration(
    commandName: "debug",
    abstract: "Commands to debug sourcekit-lsp. Intended for developers of sourcekit-lsp",
    subcommands: [
      ActiveRequestsCommand.self,
      IndexCommand.self,
      ReduceCommand.self,
      ReduceFrontendCommand.self,
      RunSourceKitdRequestCommand.self,
    ]
  )

  package init() {}
}
