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
        dependencies: ["SourceKit", "LanguageServerProtocolJSONRPC"]),

      .target(
        name: "SourceKit",

        dependencies: [
          "LanguageServerProtocol",
          "SKCore",
          "Csourcekitd",
          "SKSwiftPMWorkspace",
          "IndexStoreDB",
          // FIXME: we should break the jsonrpc dependency here.
          "LanguageServerProtocolJSONRPC",
      ]),

      .target(
        name: "SKTestSupport",
        dependencies: ["SourceKit", "ISDBTestSupport", "tibs"]),
      .testTarget(
        name: "SourceKitTests",
        dependencies: ["SourceKit", "SKTestSupport"]),

      .target(
        name: "SKSwiftPMWorkspace",
        dependencies: ["SwiftPM-auto", "SKCore"]),
      .testTarget(
        name: "SKSwiftPMWorkspaceTests",
        dependencies: ["SKSwiftPMWorkspace", "SKTestSupport"]),

      // Csourcekitd: C modules wrapper for sourcekitd.
      .target(
        name: "Csourcekitd",
        dependencies: []),

      // SKCore: Data structures and algorithms useful across the project, but not necessarily
      // suitable for use in other packages.
      .target(
        name: "SKCore",
        dependencies: ["LanguageServerProtocol"]),
      .testTarget(
        name: "SKCoreTests",
        dependencies: ["SKCore", "SKTestSupport"]),

      // jsonrpc: LSP connection using jsonrpc over pipes.
      .target(
        name: "LanguageServerProtocolJSONRPC",
        dependencies: ["LanguageServerProtocol"]),
      .testTarget(
        name: "LanguageServerProtocolJSONRPCTests",
        dependencies: ["LanguageServerProtocolJSONRPC", "SKTestSupport"]),

      // LanguageServerProtocol: The core LSP types, suitable for any LSP implementation.
      .target(
        name: "LanguageServerProtocol",
        dependencies: ["SKSupport"]),
      .testTarget(
        name: "LanguageServerProtocolTests",
        dependencies: ["LanguageServerProtocol", "SKTestSupport"]),

      // SKSupport: Data structures, algorithms and platform-abstraction code that might be generally
      // useful to any Swift package. Similar in spirit to SwiftPM's Basic module.
      .target(
        name: "SKSupport",
        dependencies: ["SPMUtility"]),
      .testTarget(
        name: "SKSupportTests",
        dependencies: ["SKSupport", "SKTestSupport"]),
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
