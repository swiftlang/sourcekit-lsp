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

public import Csourcekitd
import Foundation
import SourceKitD
import SwiftExtensions
import SwiftSourceKitPluginCommon

#if compiler(>=6.3)
#warning("Remove sourcekitd_plugin_initialize when we no longer support toolchains that call it")
#endif

/// Legacy plugin initialization logic in which sourcekitd does not inform the plugin about the sourcekitd path it was
/// loaded from.
@_cdecl("sourcekitd_plugin_initialize")
public func sourcekitd_plugin_initialize(_ params: sourcekitd_api_plugin_initialize_params_t) {
  #if canImport(Darwin)
  var dlInfo = Dl_info()
  dladdr(#dsohandle, &dlInfo)
  let path = String(cString: dlInfo.dli_fname)
  let clientPluginDylibUrl = URL(fileURLWithPath: path, isDirectory: false)
  var url = clientPluginDylibUrl
  while url.pathExtension != "framework" && url.lastPathComponent != "/" {
    url.deleteLastPathComponent()
  }
  url =
    url
    .deletingLastPathComponent()
    .appendingPathComponent("sourcekitd.framework")
    .appendingPathComponent("sourcekitd")
  if !FileManager.default.fileExists(at: url),
    let clientPluginDylibUrlRealpath = try? clientPluginDylibUrl.realpath.filePath,
    let sourcekitdPath = ProcessInfo.processInfo.environment[
      "SOURCEKIT_LSP_PLUGIN_SOURCEKITD_PATH_\(clientPluginDylibUrlRealpath)"
    ]
  {
    // When using a SourceKit plugin from the build directory, we can't find sourcekitd relative to the plugin.
    // Respect the sourcekitd path that was passed to us via an environment variable from
    // `SourceKitD.getOrCreate`.
    url = URL(fileURLWithPath: sourcekitdPath)
  }
  try! url.filePath.withCString { sourcekitdPath in
    sourcekitd_plugin_initialize_2(params, sourcekitdPath)
  }
  #else
  fatalError("sourcekitd_plugin_initialize is not supported on non-Darwin platforms")
  #endif
}

@_cdecl("sourcekitd_plugin_initialize_2")
public func sourcekitd_plugin_initialize_2(
  _ params: sourcekitd_api_plugin_initialize_params_t,
  _ sourcekitdPath: UnsafePointer<CChar>
) {
  SourceKitD.forPlugin = try! SourceKitD(
    dylib: URL(fileURLWithPath: String(cString: sourcekitdPath)),
    pluginPaths: nil,
    initialize: false
  )
  let sourcekitd = SourceKitD.forPlugin

  let customBufferStart = sourcekitd.pluginApi.plugin_initialize_custom_buffer_start(params)
  let arrayBuffKind = customBufferStart
  sourcekitd.pluginApi.plugin_initialize_register_custom_buffer(
    params,
    arrayBuffKind,
    CompletionResultsArray.arrayFuncs.rawValue
  )
}
