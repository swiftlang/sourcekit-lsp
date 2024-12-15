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
    guard try ConfigSchemaGen.verify() else {
      throw ExitCode.failure
    }
    print("All schemas are up-to-date!")
  }
}
