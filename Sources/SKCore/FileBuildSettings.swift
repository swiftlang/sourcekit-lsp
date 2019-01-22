//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Build settings for a single file.
///
/// Encapsulates all the settings needed to compile a single file, including the compiler arguments,
/// working directory, and preferred toolchain if any. FileBuildSettings are typically the result
/// of a BuildSystem query.
public struct FileBuildSettings {

  /// The Toolchain that is preferred for compiling this file, if any.
  public var preferredToolchain: Toolchain? = nil

  /// The compiler arguments to use for this file.
  public var compilerArguments: [String]

  /// The working directory to resolve any relative paths in `compilerArguments`.
  public var workingDirectory: String? = nil

  public init(
    preferredToolchain: Toolchain? = nil,
    compilerArguments: [String],
    workingDirectory: String? = nil)
  {
    self.preferredToolchain = preferredToolchain
    self.compilerArguments = compilerArguments
    self.workingDirectory = workingDirectory
  }
}
