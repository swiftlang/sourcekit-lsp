// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ConfigSchemaGen",
  platforms: [.macOS(.v10_15)],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1")
  ],
  targets: [
    .executableTarget(
      name: "ConfigSchemaGen",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    )
  ]
)
