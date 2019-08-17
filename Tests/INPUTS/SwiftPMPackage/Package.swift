// swift-tools-version:5.1

import PackageDescription

let package = Package(
  name: "SwiftPMPackage",
  products: [],
  dependencies: [],
  targets: [
    .target(
      name: "exec",
      dependencies: ["lib"]),
    .target(
      name: "lib",
      dependencies: []),
  ]
)
