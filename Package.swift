// swift-tools-version: 5.10

import Foundation
import PackageDescription

/// Swift settings that should be applied to every Swift target.
let globalSwiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
]

var products: [Product] = [
  .executable(name: "sourcekit-lsp", targets: ["sourcekit-lsp"]),
  .library(name: "_SourceKitLSP", targets: ["SourceKitLSP"]),
  .library(name: "LSPBindings", targets: ["LanguageServerProtocol", "LanguageServerProtocolJSONRPC"]),
]

var targets: [Target] = [
  // Formatting style:
  //  - One section for each target and its test target
  //  - Sections are sorted alphabetically
  //  - Dependencies are listed on separate lines
  //  - All array elements are sorted alphabetically

  // MARK: sourcekit-lsp

  .executableTarget(
    name: "sourcekit-lsp",
    dependencies: [
      "BuildSystemIntegration",
      "Diagnose",
      "LanguageServerProtocol",
      "LanguageServerProtocolExtensions",
      "LanguageServerProtocolJSONRPC",
      "SKOptions",
      "SourceKitLSP",
      "ToolchainRegistry",
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings,
    linkerSettings: sourcekitLSPLinkSettings
  ),

  // MARK: BuildServerProtocol

  .target(
    name: "BuildServerProtocol",
    dependencies: [
      "LanguageServerProtocol"
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "BuildServerProtocolTests",
    dependencies: [
      "BuildServerProtocol",
      "LanguageServerProtocol",
      "SKTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: BuildSystemIntegration

  .target(
    name: "BuildSystemIntegration",
    dependencies: [
      "BuildServerProtocol",
      "LanguageServerProtocol",
      "LanguageServerProtocolExtensions",
      "LanguageServerProtocolJSONRPC",
      "SKLogging",
      "SKOptions",
      "SKUtilities",
      "SourceKitD",
      "SwiftExtensions",
      "ToolchainRegistry",
      "TSCExtensions",
      .product(name: "SwiftPM-auto", package: "swift-package-manager"),
      .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "BuildSystemIntegrationTests",
    dependencies: [
      "BuildSystemIntegration",
      "LanguageServerProtocol",
      "SKOptions",
      "SKTestSupport",
      "SourceKitLSP",
      "ToolchainRegistry",
      "TSCExtensions",
    ],
    swiftSettings: globalSwiftSettings
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
      "BuildSystemIntegration",
      "InProcessClient",
      "LanguageServerProtocolExtensions",
      "SKLogging",
      "SKOptions",
      "SKUtilities",
      "SourceKitD",
      "SourceKitLSP",
      "SwiftExtensions",
      "ToolchainRegistry",
      "TSCExtensions",
      .product(name: "ArgumentParser", package: "swift-argument-parser"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ] + swiftSyntaxDependencies(["SwiftIDEUtils", "SwiftSyntax", "SwiftParser"]),
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "DiagnoseTests",
    dependencies: [
      "BuildSystemIntegration",
      "Diagnose",
      "SKLogging",
      "SKTestSupport",
      "SourceKitD",
      "ToolchainRegistry",
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: InProcessClient

  .target(
    name: "InProcessClient",
    dependencies: [
      "BuildSystemIntegration",
      "LanguageServerProtocol",
      "SKLogging",
      "SKOptions",
      "SourceKitLSP",
      "ToolchainRegistry",
      "TSCExtensions",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: LanguageServerProtocol

  .target(
    name: "LanguageServerProtocol",
    dependencies: [],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "LanguageServerProtocolTests",
    dependencies: [
      "LanguageServerProtocol",
      "SKTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: LanguageServerProtocolExtensions

  .target(
    name: "LanguageServerProtocolExtensions",
    dependencies: [
      "LanguageServerProtocol",
      "LanguageServerProtocolJSONRPC",
      "SKLogging",
      "SourceKitD",
      "SwiftExtensions",
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: LanguageServerProtocolJSONRPC

  .target(
    name: "LanguageServerProtocolJSONRPC",
    dependencies: [
      "LanguageServerProtocol",
      "SKLogging",
      "SwiftExtensions",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "LanguageServerProtocolJSONRPCTests",
    dependencies: [
      "LanguageServerProtocolJSONRPC",
      "SKTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SemanticIndex

  .target(
    name: "SemanticIndex",
    dependencies: [
      "BuildSystemIntegration",
      "LanguageServerProtocol",
      "SKLogging",
      "SwiftExtensions",
      "ToolchainRegistry",
      "TSCExtensions",
      .product(name: "IndexStoreDB", package: "indexstore-db"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "SemanticIndexTests",
    dependencies: [
      "SemanticIndex",
      "SKLogging",
      "SKTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SKLogging

  .target(
    name: "SKLogging",
    dependencies: [
      "SwiftExtensions",
      .product(name: "Crypto", package: "swift-crypto"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings + lspLoggingSwiftSettings
  ),

  .testTarget(
    name: "SKLoggingTests",
    dependencies: [
      "SKLogging",
      "SKTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SKOptions

  .target(
    name: "SKOptions",
    dependencies: [
      "LanguageServerProtocol",
      "LanguageServerProtocolExtensions",
      "SKLogging",
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SKUtilities

  .target(
    name: "SKUtilities",
    dependencies: [
      "SKLogging",
      "SwiftExtensions",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "SKUtilitiesTests",
    dependencies: [
      "SKUtilities",
      "SKTestSupport",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SKTestSupport

  .target(
    name: "SKTestSupport",
    dependencies: [
      "BuildSystemIntegration",
      "CSKTestSupport",
      "InProcessClient",
      "LanguageServerProtocol",
      "LanguageServerProtocolExtensions",
      "LanguageServerProtocolJSONRPC",
      "SKLogging",
      "SKOptions",
      "SKUtilities",
      "SourceKitLSP",
      "SwiftExtensions",
      "ToolchainRegistry",
      "TSCExtensions",
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    resources: [.copy("INPUTS")],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SourceKitD

  .target(
    name: "SourceKitD",
    dependencies: [
      "Csourcekitd",
      "SKLogging",
      "SwiftExtensions",
    ],
    exclude: ["CMakeLists.txt", "sourcekitd_uids.swift.gyb"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "SourceKitDTests",
    dependencies: [
      "BuildSystemIntegration",
      "SourceKitD",
      "SKTestSupport",
      "SwiftExtensions",
      "ToolchainRegistry",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SourceKitLSP

  .target(
    name: "SourceKitLSP",
    dependencies: [
      "BuildServerProtocol",
      "BuildSystemIntegration",
      "LanguageServerProtocol",
      "LanguageServerProtocolExtensions",
      "LanguageServerProtocolJSONRPC",
      "SemanticIndex",
      "SKLogging",
      "SKOptions",
      "SKUtilities",
      "SourceKitD",
      "SwiftExtensions",
      "ToolchainRegistry",
      "TSCExtensions",
      .product(name: "IndexStoreDB", package: "indexstore-db"),
      .product(name: "Crypto", package: "swift-crypto"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      .product(name: "SwiftPM-auto", package: "swift-package-manager"),
    ]
      + swiftSyntaxDependencies([
        "SwiftBasicFormat", "SwiftDiagnostics", "SwiftIDEUtils", "SwiftParser", "SwiftParserDiagnostics",
        "SwiftRefactor", "SwiftSyntax",
      ]),
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "SourceKitLSPTests",
    dependencies: [
      "BuildServerProtocol",
      "BuildSystemIntegration",
      "LanguageServerProtocol",
      "LanguageServerProtocolExtensions",
      "SemanticIndex",
      "SKLogging",
      "SKOptions",
      "SKTestSupport",
      "SKUtilities",
      "SourceKitD",
      "SourceKitLSP",
      "ToolchainRegistry",
      .product(name: "IndexStoreDB", package: "indexstore-db"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      // Depend on `SwiftCompilerPlugin` and `SwiftSyntaxMacros` so the modules are built before running tests and can
      // be used by test cases that test macros (see `SwiftPMTestProject.macroPackageManifest`)
    ] + swiftSyntaxDependencies(["SwiftParser", "SwiftSyntax", "SwiftCompilerPlugin", "SwiftSyntaxMacros"]),
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SwiftExtensions

  .target(
    name: "SwiftExtensions",
    dependencies: ["CAtomics"],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "SwiftExtensionsTests",
    dependencies: [
      "SKLogging",
      "SKTestSupport",
      "SwiftExtensions",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: ToolchainRegistry

  .target(
    name: "ToolchainRegistry",
    dependencies: [
      "LanguageServerProtocolExtensions",
      "SKLogging",
      "SKUtilities",
      "SwiftExtensions",
      "TSCExtensions",
      .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "ToolchainRegistryTests",
    dependencies: [
      "SKTestSupport",
      "ToolchainRegistry",
      .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: TSCExtensions

  .target(
    name: "TSCExtensions",
    dependencies: [
      "SKLogging",
      "SwiftExtensions",
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "TSCExtensionsTests",
    dependencies: [
      "SKTestSupport",
      "SwiftExtensions",
      "TSCExtensions",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),
]

if buildOnlyTests {
  products = []
  targets = targets.compactMap { target in
    guard target.isTest || target.name == "SKTestSupport" else {
      return nil
    }
    target.dependencies = target.dependencies.filter { dependency in
      if case .byNameItem(name: "SKTestSupport", _) = dependency {
        return true
      }
      return false
    }
    return target
  }
}

let package = Package(
  name: "SourceKitLSP",
  platforms: [.macOS(.v13)],
  products: products,
  dependencies: dependencies,
  targets: targets,
  swiftLanguageVersions: [.v5, .version("6")]
)

func swiftSyntaxDependencies(_ names: [String]) -> [Target.Dependency] {
  if buildDynamicSwiftSyntaxLibrary {
    return [.product(name: "_SwiftSyntaxDynamic", package: "swift-syntax")]
  } else {
    return names.map { .product(name: $0, package: "swift-syntax") }
  }
}

// MARK: - Parse build arguments

func hasEnvironmentVariable(_ name: String) -> Bool {
  return ProcessInfo.processInfo.environment[name] != nil
}

/// Use the `NonDarwinLogger` even if `os_log` can be imported.
///
/// This is useful when running tests using `swift test` because xctest will not display the output from `os_log` on the
/// command line.
var forceNonDarwinLogger: Bool { hasEnvironmentVariable("SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER") }

// When building the toolchain on the CI, don't add the CI's runpath for the
// final build before installing.
var installAction: Bool { hasEnvironmentVariable("SOURCEKIT_LSP_CI_INSTALL") }

/// Assume that all the package dependencies are checked out next to sourcekit-lsp and use that instead of fetching a
/// remote dependency.
var useLocalDependencies: Bool { hasEnvironmentVariable("SWIFTCI_USE_LOCAL_DEPS") }

/// Whether swift-syntax is being built as a single dynamic library instead of as a separate library per module.
///
/// This means that the swift-syntax symbols don't need to be statically linked, which allows us to stay below the
/// maximum number of exported symbols on Windows, in turn allowing us to build sourcekit-lsp using SwiftPM on Windows
/// and run its tests.
var buildDynamicSwiftSyntaxLibrary: Bool { hasEnvironmentVariable("SWIFTSYNTAX_BUILD_DYNAMIC_LIBRARY") }

/// Build only tests targets and test support modules.
///
/// This is used to test swift-format on Windows, where the modules required for the `swift-format` executable are
/// built using CMake. When using this setting, the caller is responsible for passing the required search paths to
/// the `swift test` invocation so that all pre-built modules can be found.
var buildOnlyTests: Bool { hasEnvironmentVariable("SOURCEKIT_LSP_BUILD_ONLY_TESTS") }

// MARK: - Dependencies

// When building with the swift build-script, use local dependencies whose contents are controlled
// by the external environment. This allows sourcekit-lsp to take advantage of the automation used
// for building the swift toolchain, such as `update-checkout`, or cross-repo PR tests.

var dependencies: [Package.Dependency] {
  if buildOnlyTests {
    return []
  } else if useLocalDependencies {
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
    return [.define("SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER")]
  } else {
    return []
  }
}
