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
import SwiftExtensions
import SwiftSourceKitPluginCommon

#if compiler(>=6)
public import Csourcekitd
#else
import Csourcekitd
#endif

private func useNewAPI(for dict: SKDRequestDictionaryReader) -> Bool {
  guard let opts: SKDRequestDictionaryReader = dict[dict.sourcekitd.keys.codeCompleteOptions],
    opts[dict.sourcekitd.keys.useNewAPI] == 1
  else {
    return false
  }
  return true
}

final class RequestHandler: Sendable {
  enum HandleRequestResult {
    /// `handleRequest` will call `receiver`.
    case requestHandled

    /// `handleRequest` will not call `receiver` and a request response should be produced by sourcekitd (not the plugin).
    case handleInSourceKitD
  }

  let requestHandlingQueue = AsyncQueue<Serial>()
  let sourcekitd: SourceKitD
  let completionProvider: CompletionProvider

  init(params: sourcekitd_api_plugin_initialize_params_t, completionResultsBufferKind: UInt64, sourcekitd: SourceKitD) {
    let ideInspectionInstance = sourcekitd.servicePluginApi.plugin_initialize_get_swift_ide_inspection_instance(params)

    self.sourcekitd = sourcekitd
    self.completionProvider = CompletionProvider(
      completionResultsBufferKind: completionResultsBufferKind,
      opaqueIDEInspectionInstance: OpaqueIDEInspectionInstance(ideInspectionInstance),
      sourcekitd: sourcekitd
    )
  }

  func handleRequest(
    _ dict: SKDRequestDictionaryReader,
    handle: RequestHandle?,
    receiver: @Sendable @escaping (SKDResponse) -> Void
  ) -> HandleRequestResult {
    func produceResult(
      body: @escaping @Sendable () async throws -> SKDResponseDictionaryBuilder
    ) -> HandleRequestResult {
      requestHandlingQueue.async {
        do {
          receiver(try await body().response)
        } catch {
          receiver(SKDResponse.from(error: error, sourcekitd: self.sourcekitd))
        }
      }
      return .requestHandled
    }

    func sourcekitdProducesResult(body: @escaping @Sendable () async -> ()) -> HandleRequestResult {
      requestHandlingQueue.async {
        await body()
      }
      return .handleInSourceKitD
    }

    switch dict[sourcekitd.keys.request] as sourcekitd_api_uid_t? {
    case sourcekitd.requests.editorOpen:
      return sourcekitdProducesResult {
        await self.completionProvider.handleDocumentOpen(dict)
      }
    case sourcekitd.requests.editorReplaceText:
      return sourcekitdProducesResult {
        await self.completionProvider.handleDocumentEdit(dict)
      }
    case sourcekitd.requests.editorClose:
      return sourcekitdProducesResult {
        await self.completionProvider.handleDocumentClose(dict)
      }

    case sourcekitd.requests.codeCompleteOpen:
      guard useNewAPI(for: dict) else {
        return .handleInSourceKitD
      }
      return produceResult {
        try await self.completionProvider.handleCompleteOpen(dict, handle: handle)
      }
    case sourcekitd.requests.codeCompleteUpdate:
      guard useNewAPI(for: dict) else {
        return .handleInSourceKitD
      }
      return produceResult {
        try await self.completionProvider.handleCompleteUpdate(dict)
      }
    case sourcekitd.requests.codeCompleteClose:
      guard useNewAPI(for: dict) else {
        return .handleInSourceKitD
      }
      return produceResult {
        try await self.completionProvider.handleCompleteClose(dict)
      }
    case sourcekitd.requests.codeCompleteDocumentation:
      return produceResult {
        try await self.completionProvider.handleCompletionDocumentation(dict)
      }
    case sourcekitd.requests.codeCompleteDiagnostic:
      return produceResult {
        try await self.completionProvider.handleCompletionDiagnostic(dict)
      }
    case sourcekitd.requests.codeCompleteSetPopularAPI:
      guard useNewAPI(for: dict) else {
        return .handleInSourceKitD
      }
      return produceResult {
        await self.completionProvider.handleSetPopularAPI(dict)
      }
    case sourcekitd.requests.dependencyUpdated:
      return sourcekitdProducesResult {
        await self.completionProvider.handleDependencyUpdated()
      }
    default:
      return .handleInSourceKitD
    }
  }

  func cancel(_ handle: RequestHandle) {
    self.completionProvider.cancel(handle: handle)
  }
}

/// Legacy plugin initialization logic in which sourcekitd does not inform the plugin about the sourcekitd path it was
/// loaded from.
@_cdecl("sourcekitd_plugin_initialize")
public func sourcekitd_plugin_initialize(_ params: sourcekitd_api_plugin_initialize_params_t) {
  #if canImport(Darwin)
  var dlInfo = Dl_info()
  dladdr(#dsohandle, &dlInfo)
  let path = String(cString: dlInfo.dli_fname)
  var url = URL(fileURLWithPath: path, isDirectory: false)
  while url.pathExtension != "framework" && url.lastPathComponent != "/" {
    url.deleteLastPathComponent()
  }
  url =
    url
    .deletingLastPathComponent()
    .appendingPathComponent("sourcekitd.framework")
    .appendingPathComponent("sourcekitd")
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
  DynamicallyLoadedSourceKitD.forPlugin = try! DynamicallyLoadedSourceKitD(
    dylib: URL(fileURLWithPath: String(cString: parentLibraryPath)),
    pluginPaths: nil,
    initialize: false
  )
  let sourcekitd = DynamicallyLoadedSourceKitD.forPlugin

  let completionResultsBufferKind = sourcekitd.pluginApi.plugin_initialize_custom_buffer_start(params)
  let isClientOnly = sourcekitd.pluginApi.plugin_initialize_is_client_only(params)

  let uidFromCString = sourcekitd.pluginApi.plugin_initialize_uid_get_from_cstr(params)
  let uidGetCString = sourcekitd.pluginApi.plugin_initialize_uid_get_string_ptr(params)

  // Depending on linking and loading configuration, we may need to chain the global UID handlers back to the UID
  // handlers in the caller. The extra hop should not matter, since we cache the results.
  if unsafeBitCast(uidFromCString, to: UnsafeRawPointer.self)
    != unsafeBitCast(sourcekitd.api.uid_get_from_cstr, to: UnsafeRawPointer.self)
  {
    sourcekitd.api.set_uid_handlers(uidFromCString, uidGetCString)
  }

  sourcekitd.pluginApi.plugin_initialize_register_custom_buffer(
    params,
    completionResultsBufferKind,
    CompletionResultsArray.arrayFuncs.rawValue
  )

  if isClientOnly {
    return
  }

  let requestHandler = RequestHandler(
    params: params,
    completionResultsBufferKind: completionResultsBufferKind,
    sourcekitd: sourcekitd
  )

  sourcekitd.servicePluginApi.plugin_initialize_register_cancellation_handler(params) { handle in
    if let handle = RequestHandle(handle) {
      requestHandler.cancel(handle)
    }
  }

  sourcekitd.servicePluginApi.plugin_initialize_register_cancellable_request_handler(params) {
    (request, handle, receiver) -> Bool in
    guard let receiver, let request, let dict = SKDRequestDictionaryReader(request, sourcekitd: sourcekitd) else {
      return false
    }
    let handle = RequestHandle(handle)

    let handledRequest = requestHandler.handleRequest(dict, handle: handle) { receiver($0.underlyingValueRetained()) }

    switch handledRequest {
    case .requestHandled: return true
    case .handleInSourceKitD: return false
    }
  }
}
