//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import Foundation

package struct SupportedSwiftFeature: Sendable, Equatable {
  package enum Kind: String, Sendable {
    case upcoming
    case experimental
  }

  package let name: String
  package let kind: Kind
  package let enabledIn: SwiftVersion?

  package init(name: String, kind: Kind, enabledIn: SwiftVersion?) {
    self.name = name
    self.kind = kind
    self.enabledIn = enabledIn
  }
}

package struct SupportedSwiftFeatures: Sendable, Equatable {
  package let upcoming: [SupportedSwiftFeature]
  package let experimental: [SupportedSwiftFeature]

  package init(upcoming: [SupportedSwiftFeature], experimental: [SupportedSwiftFeature]) {
    self.upcoming = upcoming
    self.experimental = experimental
  }

  package init(jsonData: Data) throws {
    let entries = try JSONDecoder().decode([FeatureEntry].self, from: jsonData)
    var upcoming: [SupportedSwiftFeature] = []
    var experimental: [SupportedSwiftFeature] = []

    for entry in entries {
      guard let name = entry.name else {
        continue
      }

      switch entry.kind {
      case "upcoming":
        upcoming.append(SupportedSwiftFeature(name: name, kind: .upcoming, enabledIn: entry.enabledInVersion))
      case "experimental":
        experimental.append(SupportedSwiftFeature(name: name, kind: .experimental, enabledIn: nil))
      default:
        continue
      }
    }

    self.init(upcoming: upcoming, experimental: experimental)
  }

  package func feature(named name: String, kind: SupportedSwiftFeature.Kind) -> SupportedSwiftFeature? {
    switch kind {
    case .upcoming:
      return upcoming.first { $0.name == name }
    case .experimental:
      return experimental.first { $0.name == name }
    }
  }

  package func contains(_ name: String, kind: SupportedSwiftFeature.Kind) -> Bool {
    return feature(named: name, kind: kind) != nil
  }
}

private struct FeatureEntry: Decodable {
  let name: String?
  let kind: String?
  let enabledIn: String?

  enum CodingKeys: String, CodingKey {
    case name
    case kind
    case enabledIn = "enabled_in"
  }

  var enabledInVersion: SwiftVersion? {
    guard let enabledIn else {
      return nil
    }
    return SwiftVersion(enabledIn)
  }
}

extension SwiftVersion {
  package init?(_ string: String) {
    let components = string.split(separator: ".")
    guard let majorText = components.first, let major = Int(majorText) else {
      return nil
    }
    let minor = components.dropFirst().first.flatMap { Int($0) } ?? 0
    self.init(major, minor)
  }
}
