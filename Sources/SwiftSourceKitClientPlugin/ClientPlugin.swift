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

import SourceKitD
import SwiftSourceKitPluginCommon

#if compiler(>=6)
public import Csourcekitd
#else
import Csourcekitd
#endif

@_cdecl("sourcekitd_plugin_initialize")
public func sourcekitd_plugin_initialize(_ params: sourcekitd_api_plugin_initialize_params_t) {
  let skd = DynamicallyLoadedSourceKitD.relativeToPlugin
  let customBufferStart = skd.pluginApi.plugin_initialize_custom_buffer_start(params)
  let arrayBuffKind = customBufferStart
  skd.pluginApi.plugin_initialize_register_custom_buffer(
    params,
    arrayBuffKind,
    CompletionResultsArray.arrayFuncs.rawValue
  )
}
