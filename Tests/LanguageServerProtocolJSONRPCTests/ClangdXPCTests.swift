//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if os(macOS)

@testable import LanguageServerProtocolJSONRPC
import Basic
import LanguageServerProtocol
import SKCore
import SourceKit
import XCTest
import SKTestSupport

private final class XPCTestMessageHandler: MessageHandler {
    func handle<Notification>(_: Notification, from: ObjectIdentifier) where Notification: NotificationType {
    }

    func handle<Request>(_: Request, id: RequestID, from: ObjectIdentifier, reply: @escaping (LSPResult<Request.Response>) -> Void) where Request: RequestType {
    }
}

final class LocalClangdXPCTests: XCTestCase {
    /// Whether to fail tests if clangd cannot be found.
    static let requireClangd: Bool = false // Note: Swift CI doesn't build clangd on all jobs

    var clangdXPCFrameworkPath: AbsolutePath?

    override func setUp() {
        let toolchains = ToolchainRegistry.shared.toolchains.filter { $0.clangdXPCFramework != nil }
        let haveClangd = !toolchains.isEmpty
        if LocalClangdXPCTests.requireClangd && !haveClangd {
            XCTFail("cannot find clangd in toolchain")
            return
        }
        if haveClangd {
            clangdXPCFrameworkPath = toolchains[0].clangdXPCFramework
        }
    }

    func testConnection() {
        guard let path = clangdXPCFrameworkPath else {
            return
        }
        guard let framework = ClangdXPCFramework(path: path) else {
            XCTFail("unable to load clangd xpc framework")
            return
        }
        let connection = JSONXPCConnection(xpc_service_name: framework.xpcBundleIdentifier)
        let handler = XPCTestMessageHandler()
        connection.start(receiveHandler: handler)
        let request = InitializeRequest(processId: 123, rootPath: nil, rootURL: nil, initializationOptions: nil, capabilities: ClientCapabilities(workspace: nil, textDocument: nil), trace: .off, workspaceFolders: nil)
        let queue = DispatchQueue(label: "result-queue")
        let group = DispatchGroup()
        group.enter()
        var initializeResult: InitializeResult?
        _ = connection.send(request, queue: queue) { result in
            if case .success(let r) = result {
                initializeResult = r
            }
            connection.close()
            group.leave()
        }
        _ = group.wait(timeout: .now() + 10)
        XCTAssertNotNil(initializeResult)
        framework.unload()
    }
}

#endif
