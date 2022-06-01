// swift-tools-version: 5.5

import PackageDescription

let package = Package(
  name: "package",
  products: [
    .library(name: "package", targets: ["package"]),
    .library(name: "otherPackage", targets: ["otherPackage"]),
  ],
  targets: [
    .target(
      name: "package",
      dependencies: []),
    .target(
      name: "otherPackage",
      dependencies: ["package"]),
  ]
)
