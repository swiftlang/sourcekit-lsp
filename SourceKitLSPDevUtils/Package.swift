// swift-tools-version: 6.0

import Foundation
import PackageDescription

let package = Package(
  name: "SourceKitLSPDevUtils",
  platforms: [.macOS(.v10_15)],
  products: [
    .executable(name: "sourcekit-lsp-dev-utils", targets: ["SourceKitLSPDevUtils"])
  ],
  targets: [
    .executableTarget(
      name: "SourceKitLSPDevUtils",
      dependencies: [
        "ConfigSchemaGen",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .target(
      name: "ConfigSchemaGen",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
  ]
)

let dependencies: [(url: String, path: String, fromVersion: Version)] = [
  ("https://github.com/swiftlang/swift-syntax.git", "../../swift-syntax", "600.0.1"),
  ("https://github.com/apple/swift-argument-parser.git", "../../swift-argument-parser", "1.5.0"),
]

if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
  package.dependencies += dependencies.map { .package(url: $0.url, from: $0.fromVersion) }
} else {
  package.dependencies += dependencies.map { .package(url: $0.path, from: $0.fromVersion) }
}
