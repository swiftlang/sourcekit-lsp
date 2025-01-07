//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SourceKitD

/// The path to the `SwiftSourceKitPluginTests` test bundle. This gives us a hook into the the build directory.
private let xctestBundle: URL = {
  #if canImport(Darwin)
  for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
    return bundle.bundleURL
  }
  preconditionFailure("Failed to find xctest bundle")
  #else
  return URL(
    fileURLWithPath: CommandLine.arguments.first!,
    relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  )
  #endif
}()

/// When running tests from Xcode, determine the build configuration of the package.
var inferedXcodeBuildConfiguration: String? {
  if let xcodeBuildDirectory = ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] {
    return URL(fileURLWithPath: xcodeBuildDirectory).lastPathComponent
  } else {
    return nil
  }
}

/// Shorthand for `FileManager.fileExists`
private func fileExists(at url: URL) -> Bool {
  return FileManager.default.fileExists(atPath: url.path)
}

/// Try to find the client and server plugin relative to `base`.
///
/// Implementation detail of `sourceKitPluginPaths` which walks up the directory structure, repeatedly calling this method.
private func pluginPaths(relativeTo base: URL) -> PluginPaths? {
  // When building in Xcode
  if let buildConfiguration = inferedXcodeBuildConfiguration {
    let frameworksDir = base.appendingPathComponent("Products")
      .appendingPathComponent(buildConfiguration)
      .appendingPathComponent("PackageFrameworks")
    let clientPlugin =
      frameworksDir
      .appendingPathComponent("SwiftSourceKitClientPlugin.framework")
      .appendingPathComponent("SwiftSourceKitClientPlugin")
    let servicePlugin =
      frameworksDir
      .appendingPathComponent("SwiftSourceKitPlugin.framework")
      .appendingPathComponent("SwiftSourceKitPlugin")
    if fileExists(at: clientPlugin) && fileExists(at: servicePlugin) {
      return PluginPaths(clientPlugin: clientPlugin, servicePlugin: servicePlugin)
    }
  }

  // When creating an `xctestproducts` bundle
  do {
    let frameworksDir = base.appendingPathComponent("PackageFrameworks")
    let clientPlugin =
      frameworksDir
      .appendingPathComponent("SwiftSourceKitClientPlugin.framework")
      .appendingPathComponent("SwiftSourceKitClientPlugin")
    let servicePlugin =
      frameworksDir
      .appendingPathComponent("SwiftSourceKitPlugin.framework")
      .appendingPathComponent("SwiftSourceKitPlugin")
    if fileExists(at: clientPlugin) && fileExists(at: servicePlugin) {
      return PluginPaths(clientPlugin: clientPlugin, servicePlugin: servicePlugin)
    }
  }

  // When building using 'swift test'
  do {
    #if canImport(Darwin)
    let dylibExtension = "dylib"
    #elseif os(Windows)
    let dylibExtension = "dll"
    #else
    let dylibExtension = "so"
    #endif
    let clientPlugin = base.appendingPathComponent("libSwiftSourceKitClientPlugin.\(dylibExtension)")
    let servicePlugin = base.appendingPathComponent("libSwiftSourceKitPlugin.\(dylibExtension)")
    if fileExists(at: clientPlugin) && fileExists(at: servicePlugin) {
      return PluginPaths(clientPlugin: clientPlugin, servicePlugin: servicePlugin)
    }
  }

  return nil
}

/// Returns the path the the client plugin and the server plugin within the current build directory.
///
/// Returns `nil` if either of the plugins can't be found in the build directory.
let sourceKitPluginPaths: PluginPaths? = {
  var base = xctestBundle
  while base.pathComponents.count > 1 {
    if let paths = pluginPaths(relativeTo: base) {
      return paths
    }
    base = base.deletingLastPathComponent()
  }
  return nil
}()
