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
import Foundation

struct VerifyConfigSchema: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract:
      "Verify that the generated JSON schema and documentation for the SourceKit-LSP configuration file are up-to-date"
  )

  func run() throws {
    let plans = try ConfigSchemaGen.plan()
    for plan in plans {
      print("Verifying \(plan.category) at \"\(plan.path.path)\"")
      let expectedContents = try plan.contents()
      let actualContents = try Data(contentsOf: plan.path)
      guard expectedContents == actualContents else {
        print("FATAL: \(plan.category) is out-of-date!")
        print("Please run `./sourcekit-lsp-dev-utils generate-config-schema` to update it.")
        throw ExitCode.failure
      }
    }
    print("All schemas are up-to-date!")
  }
}
