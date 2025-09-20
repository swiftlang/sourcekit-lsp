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

/// Legacy plugin initialization logic in which sourcekitd does not inform the plugin about the sourcekitd path it was
/// loaded from.
@_cdecl("sourcekitd_plugin_initialize")
public func sourcekitd_plugin_initialize(_ params: sourcekitd_api_plugin_initialize_params_t) {
  fatalError("sourcekitd_plugin_initialize has been removed in favor of sourcekitd_plugin_initialize_2")
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
