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

@main
struct SourceKitLSPDevUtils: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sourcekit-lsp-dev-utils",
        abstract: "Utilities for developing SourceKit-LSP",
        subcommands: [
            GenerateConfigSchema.self,
        ]
    )
}
