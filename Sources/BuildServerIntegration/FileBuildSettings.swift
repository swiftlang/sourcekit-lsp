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
@_spi(SourceKitLSP) package import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions

/// Build settings for a single file.
///
/// Encapsulates all the settings needed to compile a single file, including the compiler arguments
/// and working directory. `FileBuildSettings`` are typically the result of a build server query.
package struct FileBuildSettings: Hashable, Sendable {
  /// The compiler arguments to use for this file.
  package var compilerArguments: [String]

  /// The working directory to resolve any relative paths in `compilerArguments`.
  package var workingDirectory: String? = nil

  /// The language that the document was interpreted as, and which implies the compiler to which the build settings
  /// would be passed.
  package var language: Language

  /// Additional data about the build settings that was received from the BSP server, will not be interpreted by
  /// SourceKit-LSP but returned to clients in the `workspace/_sourceKitOptions` LSP request.
  package var data: LSPAny?

  /// Whether the build settings were computed from a real build server or whether they are synthesized fallback
  /// arguments while the build server is still busy computing build settings.
  package var isFallback: Bool

  package init(
    compilerArguments: [String],
    workingDirectory: String? = nil,
    language: Language,
    data: LSPAny? = nil,
    isFallback: Bool = false
  ) {
    self.compilerArguments = compilerArguments
    self.workingDirectory = workingDirectory
    self.language = language
    self.data = data
    self.isFallback = isFallback
  }

  /// Return arguments suitable for use by `newFile`.
  ///
  /// This patches the arguments by searching for the argument corresponding to
  /// `originalFile` and replacing it.
  package func patching(newFile: DocumentURI, originalFile: DocumentURI) -> FileBuildSettings {
    var arguments = self.compilerArguments
    // URL.lastPathComponent is only set for file URLs but we want to also infer a file extension for non-file URLs like
    // untitled:file.cpp
    let basename = originalFile.fileURL?.lastPathComponent ?? (originalFile.pseudoPath as NSString).lastPathComponent
    if let index = arguments.lastIndex(where: {
      // It's possible the arguments use relative paths while the `originalFile` given
      // is an absolute/real path value. We guess based on suffixes instead of hitting
      // the file system.
      $0.hasSuffix(basename) && originalFile.pseudoPath.hasSuffix($0)
    }) {
      arguments[index] = newFile.pseudoPath
      // The `-x<lang>` flag needs to be before the possible `-c <header file>`
      // argument in order for Clang to respect it. If there is a pre-existing `-x`
      // flag though, Clang will honor that one instead since it comes after.
      switch Language(inferredFromFileExtension: originalFile) {
      case .c: arguments.insert("-xc", at: 0)
      case .cpp: arguments.insert("-xc++", at: 0)
      case .objective_c: arguments.insert("-xobjective-c", at: 0)
      case .objective_cpp: arguments.insert("-xobjective-c++", at: 0)
      default: break
      }
    }
    return FileBuildSettings(
      compilerArguments: arguments,
      workingDirectory: self.workingDirectory,
      language: self.language,
      data: self.data,
      isFallback: self.isFallback
    )
  }
}
