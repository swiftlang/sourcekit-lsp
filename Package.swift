// swift-tools-version: 6.2

import Foundation
import PackageDescription

/// Swift settings that should be applied to every Swift target.
var globalSwiftSettings: [SwiftSetting] {
  var result: [SwiftSetting] = [
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  ]
  if noSwiftPMDependency {
    result += [.define("NO_SWIFTPM_DEPENDENCY")]
  }
  return result
}

var products: [Product] = [
  .executable(name: "sourcekit-lsp", targets: ["sourcekit-lsp"]),
  .library(name: "_SourceKitLSP", targets: ["SourceKitLSP"]),
  .library(name: "InProcessClient", targets: ["InProcessClient"]),
  .library(name: "SwiftSourceKitPlugin", type: .dynamic, targets: ["SwiftSourceKitPlugin"]),
  .library(name: "SwiftSourceKitClientPlugin", type: .dynamic, targets: ["SwiftSourceKitClientPlugin"]),
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
      "BuildServerIntegration",
      "Diagnose",
      "InProcessClient",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "LanguageServerProtocolExtensions",
      .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
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

  // MARK: BuildServerIntegration

  .target(
    name: "BuildServerIntegration",
    dependencies: [
      .product(name: "BuildServerProtocol", package: "swift-tools-protocols"),
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "LanguageServerProtocolExtensions",
      .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKOptions",
      "SKUtilities",
      "SourceKitD",
      "SwiftExtensions",
      "ToolchainRegistry",
      "TSCExtensions",
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ]
      + swiftPMDependency([
        .product(name: "SwiftPM-auto", package: "swift-package-manager"),
        .product(name: "SwiftPMDataModel-auto", package: "swift-package-manager"),
      ]),
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "BuildServerIntegrationTests",
    dependencies: [
      "BuildServerIntegration",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "SKOptions",
      "SKTestSupport",
      "SourceKitLSP",
      "ToolchainRegistry",
      "TSCExtensions",
    ],
    swiftSettings: globalSwiftSettings
  ),

  .target(
    name: "CCompletionScoring",
    dependencies: []
  ),

  // MARK: ClangLanguageService

  .target(
    name: "ClangLanguageService",
    dependencies: [
      "BuildServerIntegration",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "LanguageServerProtocolExtensions",
      .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKOptions",
      "SourceKitLSP",
      "SwiftExtensions",
      "ToolchainRegistry",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
      "TSCExtensions",
    ] + swiftSyntaxDependencies(["SwiftSyntax"]),
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: CompletionScoring

  .target(
    name: "CompletionScoring",
    dependencies: ["CCompletionScoring"],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .target(
    name: "CompletionScoringForPlugin",
    dependencies: ["CCompletionScoring"],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "CompletionScoringTests",
    dependencies: ["CompletionScoring", "CompletionScoringTestSupport", "SwiftExtensions"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "CompletionScoringPerfTests",
    dependencies: ["CompletionScoring", "CompletionScoringTestSupport", "SwiftExtensions"],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: CompletionScoringTestSupport

  .target(
    name: "CompletionScoringTestSupport",
    dependencies: [
      "CompletionScoring",
      "SwiftExtensions",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ],
    resources: [.copy("INPUTS")],
    swiftSettings: globalSwiftSettings
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
      "BuildServerIntegration",
      "InProcessClient",
      "LanguageServerProtocolExtensions",
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKOptions",
      "SKUtilities",
      "SourceKitD",
      "SourceKitLSP",
      "SwiftExtensions",
      "ToolchainRegistry",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
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
      "BuildServerIntegration",
      "Diagnose",
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKTestSupport",
      "SourceKitD",
      "ToolchainRegistry",
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: DocumentationLanguageService

  .target(
    name: "DocumentationLanguageService",
    dependencies: [
      "BuildServerIntegration",
      .product(name: "BuildServerProtocol", package: "swift-tools-protocols"),
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "SemanticIndex",
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKUtilities",
      "SourceKitLSP",
      "SwiftExtensions",
      .product(name: "IndexStoreDB", package: "indexstore-db"),
      .product(name: "Markdown", package: "swift-markdown"),
      .product(name: "SwiftDocC", package: "swift-docc"),
      .product(name: "SymbolKit", package: "swift-docc-symbolkit"),
    ],
    exclude: [],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: InProcessClient

  .target(
    name: "InProcessClient",
    dependencies: [
      "BuildServerIntegration",
      "ClangLanguageService",
      "DocumentationLanguageService",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKOptions",
      "SourceKitLSP",
      "SwiftLanguageService",
      "ToolchainRegistry",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
      "TSCExtensions",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: LanguageServerProtocolExtensions

  .target(
    name: "LanguageServerProtocolExtensions",
    dependencies: [
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SourceKitD",
      "SwiftExtensions",
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SemanticIndex

  .target(
    name: "SemanticIndex",
    dependencies: [
      .product(name: "BuildServerProtocol", package: "swift-tools-protocols"),
      "BuildServerIntegration",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "LanguageServerProtocolExtensions",
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SwiftExtensions",
      "ToolchainRegistry",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
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
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKTestSupport",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SKOptions

  .target(
    name: "SKOptions",
    dependencies: [
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "LanguageServerProtocolExtensions",
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SKUtilities

  .target(
    name: "SKUtilities",
    dependencies: [
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SwiftExtensions",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .target(
    name: "SKUtilitiesForPlugin",
    dependencies: [
      .product(name: "_SKLoggingForPlugin", package: "swift-tools-protocols"),
      "SwiftExtensionsForPlugin",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings + [
      .unsafeFlags([
        "-module-alias", "SKLogging=_SKLoggingForPlugin",
        "-module-alias", "SwiftExtensions=SwiftExtensionsForPlugin",
      ])
    ]
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
      "BuildServerIntegration",
      "CSKTestSupport",
      "Csourcekitd",
      "InProcessClient",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "LanguageServerProtocolExtensions",
      .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKOptions",
      "SKUtilities",
      "SourceKitD",
      "SourceKitLSP",
      "SwiftExtensions",
      "SwiftLanguageService",
      "ToolchainRegistry",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
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
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SwiftExtensions",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ],
    exclude: ["CMakeLists.txt", "sourcekitd_uids.swift.gyb"],
    swiftSettings: globalSwiftSettings
  ),

  .target(
    name: "SourceKitDForPlugin",
    dependencies: [
      "Csourcekitd",
      .product(name: "_SKLoggingForPlugin", package: "swift-tools-protocols"),
      "SwiftExtensionsForPlugin",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ],
    exclude: ["CMakeLists.txt", "sourcekitd_uids.swift.gyb"],
    swiftSettings: globalSwiftSettings + [
      .unsafeFlags([
        "-module-alias", "SKLogging=_SKLoggingForPlugin",
        "-module-alias", "SwiftExtensions=SwiftExtensionsForPlugin",
      ])
    ]
  ),

  .testTarget(
    name: "SourceKitDTests",
    dependencies: [
      "BuildServerIntegration",
      "SourceKitD",
      "SKTestSupport",
      "SwiftExtensions",
      "ToolchainRegistry",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SourceKitLSP

  .target(
    name: "SourceKitLSP",
    dependencies: [
      .product(name: "BuildServerProtocol", package: "swift-tools-protocols"),
      "BuildServerIntegration",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "LanguageServerProtocolExtensions",
      .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
      "SemanticIndex",
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKOptions",
      "SKUtilities",
      "SourceKitD",
      "SwiftExtensions",
      "ToolchainRegistry",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
      "TSCExtensions",
      .product(name: "IndexStoreDB", package: "indexstore-db"),
      .product(name: "Markdown", package: "swift-markdown"),
    ] + swiftSyntaxDependencies(["SwiftSyntax"]),
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "SourceKitLSPTests",
    dependencies: [
      .product(name: "BuildServerProtocol", package: "swift-tools-protocols"),
      "BuildServerIntegration",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "LanguageServerProtocolExtensions",
      "SemanticIndex",
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKOptions",
      "SKTestSupport",
      "SKUtilities",
      "SourceKitD",
      "SourceKitLSP",
      "ToolchainRegistry",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
      .product(name: "IndexStoreDB", package: "indexstore-db"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      // Depend on `SwiftCompilerPlugin` and `SwiftSyntaxMacros` so the modules are built before running tests and can
      // be used by test cases that test macros (see `SwiftPMTestProject.macroPackageManifest`)
    ]
      + swiftSyntaxDependencies([
        "SwiftIfConfig", "SwiftParser", "SwiftSyntax", "SwiftCompilerPlugin", "SwiftSyntaxMacros",
      ]),
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SwiftExtensions

  .target(
    name: "SwiftExtensions",
    dependencies: [
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols")
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .target(
    name: "SwiftExtensionsForPlugin",
    dependencies: [
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols")
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "SwiftExtensionsTests",
    dependencies: [
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKTestSupport",
      "SwiftExtensions",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SwiftLanguageService

  .target(
    name: "SwiftLanguageService",
    dependencies: [
      .product(name: "BuildServerProtocol", package: "swift-tools-protocols"),
      "BuildServerIntegration",
      "Csourcekitd",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "LanguageServerProtocolExtensions",
      .product(name: "LanguageServerProtocolTransport", package: "swift-tools-protocols"),
      "SemanticIndex",
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKOptions",
      "SKUtilities",
      "SourceKitD",
      "SourceKitLSP",
      "SwiftExtensions",
      "ToolchainRegistry",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
      "TSCExtensions",
      .product(name: "IndexStoreDB", package: "indexstore-db"),
      .product(name: "Crypto", package: "swift-crypto"),
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
    ]
      + swiftSyntaxDependencies([
        "SwiftBasicFormat",
        "SwiftDiagnostics",
        "SwiftIDEUtils",
        "SwiftParser",
        "SwiftParserDiagnostics",
        "SwiftRefactor",
        "SwiftSyntax",
        "SwiftSyntaxBuilder",
      ]),
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: SwiftSourceKitClientPlugin

  .target(
    name: "SwiftSourceKitClientPlugin",
    dependencies: [
      "Csourcekitd",
      "SourceKitDForPlugin",
      "SwiftExtensionsForPlugin",
      "SwiftSourceKitPluginCommon",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings + [
      .unsafeFlags([
        "-module-alias", "SourceKitD=SourceKitDForPlugin",
        "-module-alias", "SwiftExtensions=SwiftExtensionsForPlugin",
      ])
    ],
    linkerSettings: sourcekitLSPLinkSettings
  ),

  // MARK: SwiftSourceKitPluginCommon

  .target(
    name: "SwiftSourceKitPluginCommon",
    dependencies: [
      "Csourcekitd",
      "SourceKitDForPlugin",
      "SwiftExtensionsForPlugin",
      .product(name: "_SKLoggingForPlugin", package: "swift-tools-protocols"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings + [
      .unsafeFlags([
        "-module-alias", "SourceKitD=SourceKitDForPlugin",
        "-module-alias", "SwiftExtensions=SwiftExtensionsForPlugin",
        "-module-alias", "SKLogging=_SKLoggingForPlugin",
      ])
    ]
  ),

  // MARK: SwiftSourceKitPlugin

  .target(
    name: "SwiftSourceKitPlugin",
    dependencies: [
      "Csourcekitd",
      "CompletionScoringForPlugin",
      "SKUtilitiesForPlugin",
      .product(name: "_SKLoggingForPlugin", package: "swift-tools-protocols"),
      "SourceKitDForPlugin",
      "SwiftSourceKitPluginCommon",
      "SwiftExtensionsForPlugin",
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings + [
      .unsafeFlags([
        "-module-alias", "CompletionScoring=CompletionScoringForPlugin",
        "-module-alias", "SKUtilities=SKUtilitiesForPlugin",
        "-module-alias", "SourceKitD=SourceKitDForPlugin",
        "-module-alias", "SKLogging=_SKLoggingForPlugin",
        "-module-alias", "SwiftExtensions=SwiftExtensionsForPlugin",
      ])
    ],
    linkerSettings: sourcekitLSPLinkSettings
  ),

  .testTarget(
    name: "SwiftSourceKitPluginTests",
    dependencies: [
      "BuildServerIntegration",
      "CompletionScoring",
      "Csourcekitd",
      .product(name: "LanguageServerProtocol", package: "swift-tools-protocols"),
      "SKTestSupport",
      "SourceKitD",
      "SwiftExtensions",
      "ToolchainRegistry",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: ToolchainRegistry

  .target(
    name: "ToolchainRegistry",
    dependencies: [
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SKUtilities",
      "SwiftExtensions",
      "TSCExtensions",
    ],
    exclude: ["CMakeLists.txt"],
    swiftSettings: globalSwiftSettings
  ),

  .testTarget(
    name: "ToolchainRegistryTests",
    dependencies: [
      "SKTestSupport",
      "ToolchainRegistry",
    ],
    swiftSettings: globalSwiftSettings
  ),

  // MARK: TSCExtensions

  .target(
    name: "TSCExtensions",
    dependencies: [
      .product(name: "SKLogging", package: "swift-tools-protocols"),
      "SwiftExtensions",
      .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
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
      .product(name: "ToolsProtocolsSwiftExtensions", package: "swift-tools-protocols"),
    ],
    swiftSettings: globalSwiftSettings
  ),
]

if buildOnlyTests {
  products = []
  targets = targets.compactMap { target in
    guard target.isTest || target.name.contains("TestSupport") else {
      return nil
    }
    target.dependencies = target.dependencies.filter { dependency in
      if case .byNameItem(name: let name, _) = dependency, name.contains("TestSupport") {
        return true
      }
      return false
    }
    return target
  }
}

let package = Package(
  name: "SourceKitLSP",
  platforms: [.macOS(.v14)],
  products: products,
  dependencies: dependencies,
  targets: targets,
  swiftLanguageModes: [.v6]
)

@MainActor
func swiftSyntaxDependencies(_ names: [String]) -> [Target.Dependency] {
  if buildDynamicSwiftSyntaxLibrary {
    return [.product(name: "_SwiftSyntaxDynamic", package: "swift-syntax")]
  } else {
    return names.map { .product(name: $0, package: "swift-syntax") }
  }
}

@MainActor
func swiftPMDependency<T>(_ values: [T]) -> [T] {
  if noSwiftPMDependency {
    return []
  }
  return values
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

/// Build SourceKit-LSP without a dependency on SwiftPM, ie. without support for SwiftPM projects.
var noSwiftPMDependency: Bool { hasEnvironmentVariable("SOURCEKIT_LSP_NO_SWIFTPM_DEPENDENCY") }

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
      .package(path: "../swift-docc"),
      .package(path: "../swift-docc-symbolkit"),
      .package(path: "../swift-markdown"),
      .package(path: "../swift-tools-protocols"),
      .package(path: "../swift-tools-support-core"),
      .package(path: "../swift-argument-parser"),
      .package(path: "../swift-syntax"),
      .package(path: "../swift-crypto"),
    ] + swiftPMDependency([.package(name: "swift-package-manager", path: "../swiftpm")])
  } else {
    let relatedDependenciesBranch = "main"

    return [
      .package(url: "https://github.com/swiftlang/indexstore-db.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/swiftlang/swift-docc.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/swiftlang/swift-docc-symbolkit.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/swiftlang/swift-tools-protocols.git", from: "0.0.1"),
      .package(url: "https://github.com/swiftlang/swift-tools-support-core.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.1"),
      .package(url: "https://github.com/swiftlang/swift-syntax.git", branch: relatedDependenciesBranch),
      .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
      // Not a build dependency. Used so the "Format Source Code" command plugin can be used to format sourcekit-lsp
      .package(url: "https://github.com/swiftlang/swift-format.git", branch: relatedDependenciesBranch),
    ]
      + swiftPMDependency([
        .package(url: "https://github.com/swiftlang/swift-package-manager.git", branch: relatedDependenciesBranch)
      ])
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
