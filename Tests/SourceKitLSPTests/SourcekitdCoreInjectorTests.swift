//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Csourcekitd
import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import SourceKitD
import SourceKitLSP
import SwiftExtensions
@_spi(Testing) import SwiftLanguageService
import ToolchainRegistry
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions
import XCTest

final class SourcekitdCoreInjectorTests: SourceKitLSPTestCase {
  func testSourcekitdCoreInjectorIsNilByDefault() {
    let hooks = Hooks()
    XCTAssertNil(hooks.sourcekitdCoreInjector)
  }

  /// Verifies that when `sourcekitdCoreInjector` returns a pre-initialized `SourceKitDCore`,
  /// `SwiftLanguageService` uses it to create the `SourceKitD` connection and can process requests.
  func testSourcekitdCoreInjectorIsUsedBySwiftLanguageService() async throws {
    let toolchain = try unwrap(await ToolchainRegistry.forTesting.default)
    let sourcekitdPath = try unwrap(toolchain.sourcekitd)

    // Pre-load sourcekitd so that dlopen with RTLD_NOLOAD below can succeed and also
    // so the dylib is fully initialized before we borrow its handle.
    _ = try await SourceKitD.getOrCreate(dylibPath: sourcekitdPath, pluginPaths: sourceKitPluginPaths)

    let injectedCore = try InjectedSourceKitDCore(realDylibPath: sourcekitdPath)
    let injectorCallCount = ThreadSafeBox(initialValue: 0)
    let capturedToolchainURL = ThreadSafeBox<URL?>(initialValue: nil)

    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    let testClient = try await TestSourceKitLSPClient(
      hooks: Hooks(sourcekitdCoreInjector: { toolchainURL in
        injectorCallCount.withLock { $0 += 1 }
        capturedToolchainURL.withLock { $0 = toolchainURL }
        return injectedCore
      })
    )

    let positions = testClient.openDocument(
      "func 1️⃣foo() -> Int { 42 }",
      uri: uri
    )
    let swiftLS = try await unwrap(testClient.primaryLanguageService(for: uri) as? SwiftLanguageService)

    // The injector must have been called with the toolchain root (not the sourcekitd dylib path).
    XCTAssertGreaterThan(injectorCallCount.value, 0)
    XCTAssertEqual(capturedToolchainURL.value, toolchain.path)

    // The injected core must have had initializeService called (i.e. SourceKitD was
    // created with our core, not the cached shared one).
    XCTAssertEqual(injectedCore.initializeServiceCallCount, 1)

    // Verify the SourceKitD instance held by SwiftLanguageService actually uses our core.
    let usedCore = await swiftLS.sourcekitd.core
    XCTAssert(usedCore as AnyObject === injectedCore)

    // Verify that sourcekitd requests work through the injected core.
    // discard - we just need it not to throw
    _ = try await testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(url), position: positions["1️⃣"])
    )
  }
}

// MARK: - InjectedSourceKitDCore

/// A `SourceKitDCore` that borrows the handle of an already-loaded sourcekitd dylib without
/// calling `initialize()`, simulating a pre-initialized connection supplied by an embedding host.
/// It uses a unique fake `path` so the `SourceKitDRegistry` never deduplicates it with the
/// shared instance, ensuring `SourceKitD.init(core:)` is actually called with this core.
private final class InjectedSourceKitDCore: SourceKitDCore, Sendable {
  let dlHandle: DLHandle
  /// Unique path so this core is never found in `SourceKitDRegistry.shared`.
  let path: URL

  private let _initializeServiceCallCount = ThreadSafeBox(initialValue: 0)
  var initializeServiceCallCount: Int { _initializeServiceCallCount.value }

  init(realDylibPath: URL) throws {
    #if os(Windows)
    let dlopenModes: DLOpenFlags = []
    #else
    let dlopenModes: DLOpenFlags = [.lazy, .local, .first]
    #endif
    self.dlHandle = try dlopen(realDylibPath.filePath, mode: dlopenModes)
    self.path = URL(fileURLWithPath: "/mock/injected-sourcekitd-\(UUID().uuidString).dylib")
  }

  deinit {
    // We opened with normal flags (not RTLD_NOLOAD), so close() correctly decrements the count.
    // We do NOT call shutdown() because we never called initialize() — lifecycle is owned by
    // the shared SourceKitDCoreImpl.
    try? dlHandle.close()
  }

  func initializeService(
    api: sourcekitd_api_functions_t,
    notificationCallback: @escaping @Sendable (sourcekitd_api_response_t) -> Void
  ) {
    _initializeServiceCallCount.withLock { $0 += 1 }
    // Deliberately a no-op: we don't call sourcekitd_set_notification_handler here because
    // that would override the handler registered by the shared SourceKitDCoreImpl. For this
    // test only hover (a direct request/response) is exercised, so notifications are not needed.
  }
}
