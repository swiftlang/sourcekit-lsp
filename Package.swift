// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "SourceKitLSP",
    products: [
    ],
    dependencies: [
      // See 'Dependencies' below.
    ],
    targets: [
      .target(
        name: "sourcekit-lsp",
        dependencies: [
          "LanguageServerProtocolJSONRPC",
          "SourceKit",
          "TSCUtility",
        ]
      ),

      .target(
        name: "SourceKit",
        dependencies: [
          "Csourcekitd",
          "BuildServerProtocol",
          "IndexStoreDB",
          "LanguageServerProtocol",
          "LanguageServerProtocolJSONRPC",
          "SKCore",
          "SKSwiftPMWorkspace",
          "TSCUtility",
        ]
      ),

      .target(
        name: "SKTestSupport",
        dependencies: [
          "ISDBTestSupport",
          "LSPTestSupport",
          "SourceKit",
          "tibs", // Never imported, needed at runtime
          "TSCUtility",
        ]
      ),
      .testTarget(
        name: "SourceKitTests",
        dependencies: [
          "SKTestSupport",
          "SourceKit",
        ]
      ),

      .target(
        name: "SKSwiftPMWorkspace",
        dependencies: [
          "BuildServerProtocol",
          "LanguageServerProtocol",
          "SKCore",
          "SwiftPM-auto",
        ]
      ),
      .testTarget(
        name: "SKSwiftPMWorkspaceTests",
        dependencies: [
          "SKSwiftPMWorkspace",
          "SKTestSupport",
          "TSCUtility",
        ]
      ),

      // Csourcekitd: C modules wrapper for sourcekitd.
      .target(
        name: "Csourcekitd",
        dependencies: []
      ),

      // SKCore: Data structures and algorithms useful across the project, but not necessarily
      // suitable for use in other packages.
      .target(
        name: "SKCore",
        dependencies: [
          "BuildServerProtocol",
          "LanguageServerProtocol",
          "LanguageServerProtocolJSONRPC",
          "SKSupport",
          "TSCUtility",
        ]
      ),
      .testTarget(
        name: "SKCoreTests",
        dependencies: [
          "SKCore",
          "SKTestSupport",
        ]
      ),

      // Logging support used in LSP modules.
      .target(
        name: "LSPLogging",
        dependencies: []
      ),

      .testTarget(
        name: "LSPLoggingTests",
        dependencies: [
          "LSPLogging",
        ]
      ),

      .target(
        name: "LSPTestSupport",
        dependencies: [
          "LanguageServerProtocol",
          "LanguageServerProtocolJSONRPC"
        ]
      ),

      // jsonrpc: LSP connection using jsonrpc over pipes.
      .target(
        name: "LanguageServerProtocolJSONRPC",
        dependencies: [
          "LanguageServerProtocol",
          "LSPLogging",
        ]
      ),
      .testTarget(
        name: "LanguageServerProtocolJSONRPCTests",
        dependencies: [
          "LanguageServerProtocolJSONRPC",
          "LSPTestSupport"
        ]
      ),

      // LanguageServerProtocol: The core LSP types, suitable for any LSP implementation.
      .target(
        name: "LanguageServerProtocol",
        dependencies: []
      ),
      .testTarget(
        name: "LanguageServerProtocolTests",
        dependencies: [
          "LanguageServerProtocol",
          "LSPTestSupport",
        ]
      ),

      // BuildServerProtocol: connection between build server and language server to provide build and index info
      .target(
        name: "BuildServerProtocol",
        dependencies: [
          "LanguageServerProtocol"
        ]
      ),

      // SKSupport: Data structures, algorithms and platform-abstraction code that might be generally
      // useful to any Swift package. Similar in spirit to SwiftPM's Basic module.
      .target(
        name: "SKSupport",
        dependencies: [
          "TSCUtility"
        ]
      ),
      .testTarget(
        name: "SKSupportTests",
        dependencies: [
          "LSPTestSupport",
          "SKSupport",
          "SKTestSupport",
        ]
      ),
    ]
)

// MARK: Dependencies

// When building with the swift build-script, use local dependencies whose contents are controlled
// by the external environment. This allows sourcekit-lsp to take advantage of the automation used
// for building the swift toolchain, such as `update-checkout`, or cross-repo PR tests.

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

if getenv("SWIFTCI_USE_LOCAL_DEPS") == nil {
  // Building standalone.
  package.dependencies += [
    .package(url: "https://github.com/apple/indexstore-db.git", .branch("master")),
    .package(url: "https://github.com/apple/swift-package-manager.git", .branch("master")),
  ]
} else {
  package.dependencies += [
    .package(path: "../indexstore-db"),
    .package(path: "../swiftpm"),
  ]
}
