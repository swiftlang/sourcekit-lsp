// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SourceKitLSPDevUtils",
  platforms: [.macOS(.v10_15)],
  products: [
    .executable(name: "sourcekit-lsp-dev-utils", targets: ["SourceKitLSPDevUtils"])
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
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
