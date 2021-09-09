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

import Foundation
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

  public init(compilerArguments: [String], workingDirectory: String? = nil) {
    self.compilerArguments = compilerArguments
    self.workingDirectory = workingDirectory
  }
}

fileprivate let cExtensions = ["c"]
fileprivate let cppExtensions = ["cpp", "cc"]
fileprivate let objcExtensions = ["m"]
fileprivate let objcppExtensions = ["mm"]

private extension String {
  var pathExtension: String {
    return (self as NSString).pathExtension
  }
  var pathBasename: String {
    return (self as NSString).lastPathComponent
  }
}

public extension FileBuildSettings {
  /// Return arguments suitable for use by `newFile`.
  ///
  /// This patches the arguments by searching for the argument corresponding to
  /// `originalFile` and replacing it.
  func patching(newFile: String, originalFile: String) -> FileBuildSettings {
    var arguments = self.compilerArguments
    let basename = originalFile.pathBasename
    let fileExtension = originalFile.pathExtension
    if let index = arguments.lastIndex(where: {
      // It's possible the arguments use relative paths while the `originalFile` given
      // is an absolute/real path value. We guess based on suffixes instead of hitting
      // the file system.
      $0.hasSuffix(basename) && originalFile.hasSuffix($0)
    }) {
      arguments[index] = newFile
      // The `-x<lang>` flag needs to be before the possible `-c <header file>`
      // argument in order for Clang to respect it. If there is a pre-existing `-x`
      // flag though, Clang will honor that one instead since it comes after.
      if cExtensions.contains(fileExtension) {
        arguments.insert("-xc", at: 0)
      } else if cppExtensions.contains(fileExtension) {
        arguments.insert("-xc++", at: 0)
      } else if objcExtensions.contains(fileExtension) {
        arguments.insert("-xobjective-c", at: 0)
      } else if (objcppExtensions.contains(fileExtension)) {
        arguments.insert("-xobjective-c++", at: 0)
      }
    }
    return FileBuildSettings(compilerArguments: arguments, workingDirectory: self.workingDirectory)
  }
}
