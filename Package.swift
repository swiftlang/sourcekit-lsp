// swift-tools-version: 5.9

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

    .target(
      name: "BuildServerProtocol",
      dependencies: [
        "LanguageServerProtocol"
      ],
      exclude: ["CMakeLists.txt"]
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
        "SKCore",
        "SKLogging",
        "SKSupport",
        "SourceKitD",
        "SourceKitLSP",
        "SwiftExtensions",
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
        "LSPTestSupport",
        "SKCore",
        "SKLogging",
        "SKTestSupport",
        "SourceKitD",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ]
    ),

    // MARK: InProcessClient

    .target(
      name: "InProcessClient",
      dependencies: [
        "LanguageServerProtocol",
        "SKCore",
        "SKLogging",
        "SourceKitLSP",
      ],
      exclude: ["CMakeLists.txt"]
    ),

    // MARK: LanguageServerProtocol

    .target(
      name: "LanguageServerProtocol",
      dependencies: [],
      exclude: ["CMakeLists.txt"]
    ),

    .testTarget(
      name: "LanguageServerProtocolTests",
      dependencies: [
        "LanguageServerProtocol",
        "LSPTestSupport",
      ]
    ),

    // MARK: LanguageServerProtocolJSONRPC

    .target(
      name: "LanguageServerProtocolJSONRPC",
      dependencies: [
        "LanguageServerProtocol",
        "SKLogging",
      ],
      exclude: ["CMakeLists.txt"]
    ),

    .testTarget(
      name: "LanguageServerProtocolJSONRPCTests",
      dependencies: [
        "LanguageServerProtocolJSONRPC",
        "LSPTestSupport",
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
        "SwiftExtensions",
      ]
    ),

    // MARK: SemanticIndex

    .target(
      name: "SemanticIndex",
      dependencies: [
        "LanguageServerProtocol",
        "SKCore",
        "SKLogging",
        "SwiftExtensions",
        .product(name: "IndexStoreDB", package: "indexstore-db"),
      ],
      exclude: ["CMakeLists.txt"]
    ),

    .testTarget(
      name: "SemanticIndexTests",
      dependencies: [
        "SemanticIndex",
        "SKLogging",
        "SKTestSupport",
      ]
    ),

    // MARK: SKCore

    .target(
      name: "SKCore",
      dependencies: [
        "BuildServerProtocol",
        "LanguageServerProtocol",
        "LanguageServerProtocolJSONRPC",
        "SKLogging",
        "SKSupport",
        "SourceKitD",
        "SwiftExtensions",
        .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt"]
    ),

    .testTarget(
      name: "SKCoreTests",
      dependencies: [
        "SKCore",
        "SKTestSupport",
      ]
    ),

    // MARK: SKLogging

    .target(
      name: "SKLogging",
      dependencies: [
        "SwiftExtensions",
        .product(name: "Crypto", package: "swift-crypto"),
      ],
      exclude: ["CMakeLists.txt"],
      swiftSettings: lspLoggingSwiftSettings
    ),

    .testTarget(
      name: "SKLoggingTests",
      dependencies: [
        "SKLogging",
        "SKTestSupport",
      ]
    ),

    // MARK: SKSupport

    .target(
      name: "SKSupport",
      dependencies: [
        "CAtomics",
        "LanguageServerProtocol",
        "SKLogging",
        "SwiftExtensions",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt"]
    ),

    .testTarget(
      name: "SKSupportTests",
      dependencies: [
        "LSPTestSupport",
        "SKSupport",
        "SKTestSupport",
        "SwiftExtensions",
      ]
    ),

    // MARK: SKSwiftPMWorkspace

    .target(
      name: "SKSwiftPMWorkspace",
      dependencies: [
        "BuildServerProtocol",
        "LanguageServerProtocol",
        "SKCore",
        "SKLogging",
        "SwiftExtensions",
        .product(name: "SwiftPM-auto", package: "swift-package-manager"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt"]
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
        "SKCore",
        "SKLogging",
        "SourceKitLSP",
        "SwiftExtensions",
        .product(name: "ISDBTestSupport", package: "indexstore-db"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      resources: [.copy("INPUTS")]
    ),

    // MARK: SourceKitD

    .target(
      name: "SourceKitD",
      dependencies: [
        "Csourcekitd",
        "SKLogging",
        "SwiftExtensions",
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      ],
      exclude: ["CMakeLists.txt", "sourcekitd_uids.swift.gyb"]
    ),

    .testTarget(
      name: "SourceKitDTests",
      dependencies: [
        "SourceKitD",
        "SKCore",
        "SKTestSupport",
        "SwiftExtensions",
      ]
    ),

    // MARK: SourceKitLSP

    .target(
      name: "SourceKitLSP",
      dependencies: [
        "BuildServerProtocol",
        "LanguageServerProtocol",
        "LanguageServerProtocolJSONRPC",
        "SemanticIndex",
        "SKCore",
        "SKLogging",
        "SKSupport",
        "SKSwiftPMWorkspace",
        "SourceKitD",
        "SwiftExtensions",
        .product(name: "IndexStoreDB", package: "indexstore-db"),
        .product(name: "SwiftBasicFormat", package: "swift-syntax"),
        .product(name: "Crypto", package: "swift-crypto"),
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
        "LanguageServerProtocol",
        "LSPTestSupport",
        "SemanticIndex",
        "SKCore",
        "SKLogging",
        "SKSupport",
        "SKTestSupport",
        "SourceKitD",
        "SourceKitLSP",
        .product(name: "IndexStoreDB", package: "indexstore-db"),
        .product(name: "ISDBTestSupport", package: "indexstore-db"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
        // Depend on `SwiftCompilerPlugin` and `SwiftSyntaxMacros` so the modules are built before running tests and can
        // be used by test cases that test macros (see `SwiftPMTestProject.macroPackageManifest`).
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ]
    ),

    // MARK: SwiftExtensions

    .target(
      name: "SwiftExtensions",
      exclude: ["CMakeLists.txt"]
    ),
  ],
  swiftLanguageVersions: [.v5, .version("6")]
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
    let relatedDependenciesBranch = "main"

    return [
      .package(url: "https://github.com/swiftlang/indexstore-db.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/swiftlang/swift-package-manager.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/apple/swift-tools-support-core.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
      .package(url: "https://github.com/swiftlang/swift-syntax.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
      // Not a build dependency. Used so the "Format Source Code" command plugin can be used to format sourcekit-lsp
      .package(url: "https://github.com/swiftlang/swift-format.git", branch: relatedDependenciesBranch),
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
