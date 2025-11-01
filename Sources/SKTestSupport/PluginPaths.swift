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
@_spi(SourceKitLSP) import SKLogging
package import SourceKitD
import SwiftExtensions
import ToolchainRegistry

// Anchor class to lookup the testing bundle when swiftpm-testing-helper is used.
private final class TestingAnchor {}

/// The path to the `SwiftSourceKitPluginTests` test bundle. This gives us a hook into the the build directory.
private let xctestBundle: URL = {
  if Platform.current == .darwin {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
      return bundle.bundleURL
    }
    let bundle = Bundle(for: TestingAnchor.self)
    if bundle.bundlePath.hasSuffix(".xctest") {
      return bundle.bundleURL
    }
    preconditionFailure("Failed to find xctest bundle")
  } else {
    return URL(
      fileURLWithPath: CommandLine.arguments.first!,
      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )
  }
}()

/// When running tests from Xcode, determine the build configuration of the package.
var inferredXcodeBuildConfiguration: String? {
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
  if let buildConfiguration = inferredXcodeBuildConfiguration {
    let frameworksDir = base.appending(components: "Products", buildConfiguration, "PackageFrameworks")
    let clientPlugin =
      frameworksDir
      .appending(components: "SwiftSourceKitClientPlugin.framework", "SwiftSourceKitClientPlugin")
    let servicePlugin =
      frameworksDir
      .appending(components: "SwiftSourceKitPlugin.framework", "SwiftSourceKitPlugin")
    if fileExists(at: clientPlugin) && fileExists(at: servicePlugin) {
      return PluginPaths(clientPlugin: clientPlugin, servicePlugin: servicePlugin)
    }
  }

  // When creating an `xctestproducts` bundle
  do {
    let frameworksDir = base.appending(component: "PackageFrameworks")
    let clientPlugin =
      frameworksDir
      .appending(components: "SwiftSourceKitClientPlugin.framework", "SwiftSourceKitClientPlugin")
    let servicePlugin =
      frameworksDir
      .appending(components: "SwiftSourceKitPlugin.framework", "SwiftSourceKitPlugin")
    if fileExists(at: clientPlugin) && fileExists(at: servicePlugin) {
      return PluginPaths(clientPlugin: clientPlugin, servicePlugin: servicePlugin)
    }
  }

  // When building using 'swift test'
  do {
    let clientPluginName: String
    let servicePluginName: String
    switch Platform.current {
    case .darwin:
      clientPluginName = "libSwiftSourceKitClientPlugin.dylib"
      servicePluginName = "libSwiftSourceKitPlugin.dylib"
    case .windows:
      clientPluginName = "SwiftSourceKitClientPlugin.dll"
      servicePluginName = "SwiftSourceKitPlugin.dll"
    case .linux:
      clientPluginName = "libSwiftSourceKitClientPlugin.so"
      servicePluginName = "libSwiftSourceKitPlugin.so"
    case nil:
      logger.fault("Could not determine host OS. Falling back to using '.so' as dynamic library extension")
      clientPluginName = "libSwiftSourceKitClientPlugin.so"
      servicePluginName = "libSwiftSourceKitPlugin.so"
    }
    let clientPlugin = base.appending(component: clientPluginName)
    let servicePlugin = base.appending(component: servicePluginName)
    if fileExists(at: clientPlugin) && fileExists(at: servicePlugin) {
      return PluginPaths(clientPlugin: clientPlugin, servicePlugin: servicePlugin)
    }
  }

  return nil
}

/// Returns the paths from which the SourceKit plugins should be loaded or throws an error if the plugins cannot be
/// found.
package var sourceKitPluginPaths: PluginPaths {
  get async throws {
    struct PluginLoadingError: Error, CustomStringConvertible {
      let searchBase: URL
      var description: String {
        // We can't declare a dependency from the test *target* on the SourceKit plugin *product*
        // (https://github.com/swiftlang/swift-package-manager/issues/8245).
        // We thus require a build before running the tests to ensure the plugin dylibs are in the build products
        // folder.
        """
        Could not find SourceKit plugin. Ensure that you build the entire SourceKit-LSP package before running tests.

        Searching for plugin relative to \(searchBase)
        """
      }
    }

    var base: URL
    if let pluginPaths = ProcessInfo.processInfo.environment["SOURCEKIT_LSP_TEST_PLUGIN_PATHS"] {
      if pluginPaths == "RELATIVE_TO_SOURCEKITD" {
        let toolchain = await ToolchainRegistry.forTesting.default
        guard let clientPlugin = toolchain?.sourceKitClientPlugin, let servicePlugin = toolchain?.sourceKitServicePlugin
        else {
          throw PluginLoadingError(searchBase: URL(string: "relative-to-sourcekitd://")!)
        }
        return PluginPaths(clientPlugin: clientPlugin, servicePlugin: servicePlugin)
      } else {
        base = URL(fileURLWithPath: pluginPaths)
      }
    } else {
      base = xctestBundle
    }
    var searchPath = base
    while searchPath.pathComponents.count > 1 {
      if let paths = pluginPaths(relativeTo: searchPath) {
        return paths
      }
      searchPath = searchPath.deletingLastPathComponent()
    }

    throw PluginLoadingError(searchBase: base)
  }
}
