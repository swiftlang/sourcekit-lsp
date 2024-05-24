// swift-tools-version:5.8

import Foundation
import PackageDescription

let package = Package(
  name: "SourceKitLSP",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "sourcekit-lsp", targets: ["sourcekit-lsp"]),
    .library(name: "_SourceKitLSP", targets: ["SourceKitLSP"]),
    .library(name: "LSPBindings", targets: ["LanguageServerProtocol", "LanguageServerProtocolJSONRPC"]),
  ],
  dependencies: dependencies,
  targets: [
    // Formatting style:
    //  - One section for each target and its test target
    //  - Sections are sorted alphabetically
    //  - Dependencies are listed on separate lines
    //  - All array elements are sorted alphabetically

    // MARK: sourcekit-lsp

    .executableTarget(
      name: "sourcekit-lsp",
      dependencies: [
        "Diagnose",
        "LanguageServerProtocol",
        "LanguageServerProtocolJSONRPC",
        "SKCore",
        "SKSupport",
        "SourceKitLSP",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt"],
      linkerSettings: sourcekitLSPLinkSettings
    ),

    // MARK: BuildServerProtocol
    // Connection between build server and language server to provide build and index info

    .target(
      name: "BuildServerProtocol",
      dependencies: [
        "LanguageServerProtocol"
      ],
      exclude: ["CMakeLists.txt"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),

    // MARK: CAtomics
    .target(
      name: "CAtomics",
      dependencies: []
    ),

    // MARK: CSKTestSupport
    .target(
      name: "CSKTestSupport",
      dependencies: []
    ),

    // MARK: Csourcekitd
    // C modules wrapper for sourcekitd.
    .target(
      name: "Csourcekitd",
      dependencies: [],
      exclude: ["CMakeLists.txt"]
    ),

    // MARK: Diagnose

    .target(
      name: "Diagnose",
      dependencies: [
        "InProcessClient",
        "LSPLogging",
        "SKCore",
        "SKSupport",
        "SourceKitD",
        "SourceKitLSP",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftIDEUtils", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt"]
    ),

    .testTarget(
      name: "DiagnoseTests",
      dependencies: [
        "Diagnose",
        "LSPLogging",
        "LSPTestSupport",
        "SourceKitD",
        "SKCore",
        "SKTestSupport",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ]
    ),

    // MARK: InProcessClient

    .target(
      name: "InProcessClient",
      dependencies: [
        "CAtomics",
        "LanguageServerProtocol",
        "LSPLogging",
        "SKCore",
        "SourceKitLSP",
      ],
      exclude: ["CMakeLists.txt"]
    ),

    // MARK: LanguageServerProtocol
    // The core LSP types, suitable for any LSP implementation.
    .target(
      name: "LanguageServerProtocol",
      dependencies: [],
      exclude: ["CMakeLists.txt"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),

    .testTarget(
      name: "LanguageServerProtocolTests",
      dependencies: [
        "LanguageServerProtocol",
        "LSPTestSupport",
      ]
    ),

    // MARK: LanguageServerProtocolJSONRPC
    // LSP connection using jsonrpc over pipes.

    .target(
      name: "LanguageServerProtocolJSONRPC",
      dependencies: [
        "LanguageServerProtocol",
        "LSPLogging",
      ],
      exclude: ["CMakeLists.txt"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),

    .testTarget(
      name: "LanguageServerProtocolJSONRPCTests",
      dependencies: [
        "LanguageServerProtocolJSONRPC",
        "LSPTestSupport",
      ]
    ),

    // MARK: LSPLogging
    // Logging support used in LSP modules.

    .target(
      name: "LSPLogging",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto")
      ],
      exclude: ["CMakeLists.txt"],
      swiftSettings: lspLoggingSwiftSettings + [.enableExperimentalFeature("StrictConcurrency")]
    ),

    .testTarget(
      name: "LSPLoggingTests",
      dependencies: [
        "LSPLogging",
        "SKTestSupport",
      ]
    ),

    // MARK: LSPTestSupport

    .target(
      name: "LSPTestSupport",
      dependencies: [
        "InProcessClient",
        "LanguageServerProtocol",
        "LanguageServerProtocolJSONRPC",
        "SKSupport",
      ]
    ),

    // MARK: SemanticIndex

    .target(
      name: "SemanticIndex",
      dependencies: [
        "CAtomics",
        "LanguageServerProtocol",
        "LSPLogging",
        "SKCore",
        .product(name: "IndexStoreDB", package: "indexstore-db"),
      ],
      exclude: ["CMakeLists.txt"]
    ),

    .testTarget(
      name: "SemanticIndexTests",
      dependencies: [
        "SemanticIndex"
      ]
    ),

    // MARK: SKCore
    // Data structures and algorithms useful across the project, but not necessarily
    // suitable for use in other packages.

    .target(
      name: "SKCore",
      dependencies: [
        "BuildServerProtocol",
        "CAtomics",
        "LanguageServerProtocol",
        "LanguageServerProtocolJSONRPC",
        "LSPLogging",
        "SKSupport",
        "SourceKitD",
        .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),

    .testTarget(
      name: "SKCoreTests",
      dependencies: [
        "SKCore",
        "SKTestSupport",
      ]
    ),

    // MARK: SKSupport
    // Data structures, algorithms and platform-abstraction code that might be generally useful to any Swift package.
    // Similar in spirit to SwiftPM's Basic module.

    .target(
      name: "SKSupport",
      dependencies: [
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
        "LanguageServerProtocol",
        "LSPLogging",
      ],
      exclude: ["CMakeLists.txt"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),

    .testTarget(
      name: "SKSupportTests",
      dependencies: [
        "LSPTestSupport",
        "SKSupport",
        "SKTestSupport",
      ]
    ),

    // MARK: SKSwiftPMWorkspace

    .target(
      name: "SKSwiftPMWorkspace",
      dependencies: [
        "BuildServerProtocol",
        "LanguageServerProtocol",
        "LSPLogging",
        "SKCore",
        .product(name: "SwiftPM-auto", package: "swift-package-manager"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),

    .testTarget(
      name: "SKSwiftPMWorkspaceTests",
      dependencies: [
        "LSPTestSupport",
        "LanguageServerProtocol",
        "SKCore",
        "SKSwiftPMWorkspace",
        "SKTestSupport",
        "SourceKitLSP",
        .product(name: "SwiftPM-auto", package: "swift-package-manager"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ]
    ),

    // MARK: SKTestSupport

    .target(
      name: "SKTestSupport",
      dependencies: [
        "CSKTestSupport",
        "InProcessClient",
        "LanguageServerProtocol",
        "LSPTestSupport",
        "LSPLogging",
        "SKCore",
        "SourceKitLSP",
        .product(name: "ISDBTestSupport", package: "indexstore-db"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      resources: [
        .copy("INPUTS")
      ]
    ),

    // MARK: SourceKitD
    // Swift bindings for sourcekitd.

    .target(
      name: "SourceKitD",
      dependencies: [
        "Csourcekitd",
        "LSPLogging",
        "SKSupport",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt", "sourcekitd_uids.swift.gyb"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),

    .testTarget(
      name: "SourceKitDTests",
      dependencies: [
        "SourceKitD",
        "SKCore",
        "SKTestSupport",
      ]
    ),

    // MARK: SourceKitLSP

    .target(
      name: "SourceKitLSP",
      dependencies: [
        "BuildServerProtocol",
        "CAtomics",
        "LanguageServerProtocol",
        "LanguageServerProtocolJSONRPC",
        "LSPLogging",
        "SemanticIndex",
        "SKCore",
        "SKSupport",
        "SKSwiftPMWorkspace",
        "SourceKitD",
        .product(name: "IndexStoreDB", package: "indexstore-db"),
        .product(name: "SwiftBasicFormat", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftIDEUtils", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftRefactor", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
        .product(name: "SwiftPM-auto", package: "swift-package-manager"),
      ],
      exclude: ["CMakeLists.txt"]
    ),

    .testTarget(
      name: "SourceKitLSPTests",
      dependencies: [
        "BuildServerProtocol",
        "LSPLogging",
        "LSPTestSupport",
        "LanguageServerProtocol",
        "SKCore",
        "SKSupport",
        "SKTestSupport",
        "SourceKitD",
        "SourceKitLSP",
        .product(name: "IndexStoreDB", package: "indexstore-db"),
        .product(name: "ISDBTestSupport", package: "indexstore-db"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ]
    ),
  ]
)

// MARK: - Parse build arguments

func hasEnvironmentVariable(_ name: String) -> Bool {
  return ProcessInfo.processInfo.environment[name] != nil
}

/// Use the `NonDarwinLogger` even if `os_log` can be imported.
///
/// This is useful when running tests using `swift test` because xctest will not display the output from `os_log` on the
/// command line.
var forceNonDarwinLogger: Bool { hasEnvironmentVariable("SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER") }

// When building the toolchain on the CI, don't add the CI's runpath for the
// final build before installing.
var installAction: Bool { hasEnvironmentVariable("SOURCEKIT_LSP_CI_INSTALL") }

/// Assume that all the package dependencies are checked out next to sourcekit-lsp and use that instead of fetching a
/// remote dependency.
var useLocalDependencies: Bool { hasEnvironmentVariable("SWIFTCI_USE_LOCAL_DEPS") }

// MARK: - Dependencies

// When building with the swift build-script, use local dependencies whose contents are controlled
// by the external environment. This allows sourcekit-lsp to take advantage of the automation used
// for building the swift toolchain, such as `update-checkout`, or cross-repo PR tests.

var dependencies: [Package.Dependency] {
  if useLocalDependencies {
    return [
      .package(path: "../indexstore-db"),
      .package(name: "swift-package-manager", path: "../swiftpm"),
      .package(path: "../swift-tools-support-core"),
      .package(path: "../swift-argument-parser"),
      .package(path: "../swift-syntax"),
      .package(path: "../swift-crypto"),
    ]
  } else {
    let relatedDependenciesBranch = "release/6.0"

    return [
      .package(url: "https://github.com/apple/indexstore-db.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/apple/swift-package-manager.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/apple/swift-tools-support-core.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.2"),
      .package(url: "https://github.com/apple/swift-syntax.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
      // Not a build dependency. Used so the "Format Source Code" command plugin can be used to format sourcekit-lsp
      .package(url: "https://github.com/apple/swift-format.git", branch: relatedDependenciesBranch),
    ]
  }
}

// MARK: - Compute custom build settings

var sourcekitLSPLinkSettings: [LinkerSetting] {
  if installAction {
    return [.unsafeFlags(["-no-toolchain-stdlib-rpath"], .when(platforms: [.linux, .android]))]
  } else {
    return []
  }
}

var lspLoggingSwiftSettings: [SwiftSetting] {
  if forceNonDarwinLogger {
    return [.define("SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER")]
  } else {
    return []
  }
}
