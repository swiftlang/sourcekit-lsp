//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

/// Build settings for a single file.
///
/// Encapsulates all the settings needed to compile a single file, including the compiler arguments
/// and working directory. FileBuildSettings are typically the result of a BuildSystem query.
public struct FileBuildSettings: Equatable {

  /// The compiler arguments to use for this file.
  public var compilerArguments: [String]

  /// The working directory to resolve any relative paths in `compilerArguments`.
  public var workingDirectory: String? = nil

  /// The language of this file.
  public var language: Language

  public init(
    compilerArguments: [String],
    workingDirectory: String? = nil,
    language: Language)
  {
    self.workingDirectory = workingDirectory
    self.language = language
    // For swift, sourcekit only accepts `working-directry` through compiler args.
    // Injecting the arg here if workingDirectory presents in the settings,
    // but not in the actual compiler args.
    var compilerArgumentsWithWorkingDirectory = compilerArguments
    if language == .swift,
      let workingDirectory = workingDirectory,
      !compilerArguments.contains("-working-directory") {
      compilerArgumentsWithWorkingDirectory += ["-working-directory", workingDirectory]
    }
    self.compilerArguments = compilerArgumentsWithWorkingDirectory
  }
}
