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
import ConfigSchemaGen

struct GenerateConfigSchema: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a JSON schema and documentation for the SourceKit-LSP configuration file"
    )

    func run() throws {
        try ConfigSchemaGen.generate()
    }
}
