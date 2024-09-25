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

#if compiler(>=6)
package import LanguageServerProtocol
package import SKOptions

import enum PackageLoading.Platform
import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
#else
import LanguageServerProtocol
import SKOptions

import enum PackageLoading.Platform
import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
#endif

/// The path to the SDK.
private let sdkpath: AbsolutePath? = {
  guard Platform.current == .darwin else { return nil }
  return try? AbsolutePath(
    validating: Process.checkNonZeroExit(args: "/usr/bin/xcrun", "--show-sdk-path", "--sdk", "macosx")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  )
}()

package func fallbackBuildSettings(
  for uri: DocumentURI,
  language: Language,
  options: SourceKitLSPOptions.FallbackBuildSystemOptions
) -> FileBuildSettings? {
  let args: [String]
  switch language {
  case .swift:
    args = fallbackBuildSettingsSwift(for: uri, options: options)
  case .c, .cpp, .objective_c, .objective_cpp:
    args = fallbackBuildSettingsClang(for: uri, language: language, options: options)
  default:
    return nil
  }
  return FileBuildSettings(compilerArguments: args, workingDirectory: nil, isFallback: true)
}

private func fallbackBuildSettingsSwift(
  for uri: DocumentURI,
  options: SourceKitLSPOptions.FallbackBuildSystemOptions
) -> [String] {
  var args: [String] = options.swiftCompilerFlags ?? []
  if let sdkpath = AbsolutePath(validatingOrNil: options.sdk) ?? sdkpath, !args.contains("-sdk") {
    args += ["-sdk", sdkpath.pathString]
  }
  args.append(uri.pseudoPath)
  return args
}

private func fallbackBuildSettingsClang(
  for uri: DocumentURI,
  language: Language,
  options: SourceKitLSPOptions.FallbackBuildSystemOptions
) -> [String] {
  var args: [String] = []
  switch language {
  case .c:
    args += options.cCompilerFlags ?? []
  case .cpp:
    args += options.cxxCompilerFlags ?? []
  default:
    break
  }
  if let sdkpath = AbsolutePath(validatingOrNil: options.sdk) ?? sdkpath, !args.contains("-isysroot") {
    args += [
      "-isysroot",
      sdkpath.pathString,
    ]
  }
  args.append(uri.pseudoPath)
  return args
}
