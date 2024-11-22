//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@preconcurrency import SwiftDocC

struct DocCSymbolLink: Sendable {
  let module: String
  let components: [AbsoluteSymbolLink.LinkComponent]

  var absoluteString: String {
    return "\(module)/\(components.map { $0.asLinkComponentString}.joined(separator: "/"))"
  }

  var representsModule: Bool {
    return components.count == 0
  }

  init(symbolLink absoluteSymbolLink: AbsoluteSymbolLink) {
    self.module = absoluteSymbolLink.module
    guard !absoluteSymbolLink.representsModule else {
      self.components = []
      return
    }
    self.components = [absoluteSymbolLink.topLevelSymbol] + absoluteSymbolLink.basePathComponents
  }

  init?(string: String) {
    guard let symbolLink = AbsoluteSymbolLink(string: string) else {
      return nil
    }
    self.init(symbolLink: symbolLink)
  }

  init?(componentsIncludingModule rawComponents: [String]) {
    var rawComponents = rawComponents.filter { !$0.isEmpty }
    guard rawComponents.count > 0 else {
      return nil
    }
    self.module = rawComponents.removeFirst()
    var components = [AbsoluteSymbolLink.LinkComponent]()
    for rawComponent in rawComponents {
      guard let component = AbsoluteSymbolLink.LinkComponent(string: rawComponent) else {
        return nil
      }
      components.append(component)
    }
    self.components = components
  }

  init?(module: String, components rawComponents: [String]) {
    self.module = module
    var components = [AbsoluteSymbolLink.LinkComponent]()
    for rawComponent in rawComponents {
      guard let component = AbsoluteSymbolLink.LinkComponent(string: rawComponent) else {
        return nil
      }
      components.append(component)
    }
    self.components = components
  }

  private init(module: String, components: [AbsoluteSymbolLink.LinkComponent]) {
    self.module = module
    self.components = components
  }

  func appending(string componentString: String) -> DocCSymbolLink? {
    guard let component = AbsoluteSymbolLink.LinkComponent(string: componentString) else {
      return nil
    }
    return .init(module: module, components: components + [component])
  }

  func appending(components rawComponents: [String]) -> DocCSymbolLink? {
    var result = self
    for rawComponent in rawComponents {
      guard let nextSymbolLink = result.appending(string: rawComponent) else {
        return nil
      }
      result = nextSymbolLink
    }
    return result
  }
}

extension DocCSymbolLink: Equatable {
  static func == (lhs: DocCSymbolLink, rhs: DocCSymbolLink) -> Bool {
    guard lhs.module == rhs.module, lhs.components.count == rhs.components.count else {
      return false
    }
    for i in 0..<lhs.components.count {
      let lhsComponent = lhs.components[i]
      let rhsComponent = rhs.components[i]
      guard lhsComponent.name == rhsComponent.name else {
        return false
      }
      if lhsComponent.disambiguationSuffix != .none, rhsComponent.disambiguationSuffix != .none {
        guard lhsComponent.disambiguationSuffix == rhsComponent.disambiguationSuffix else {
          return false
        }
      }
    }
    return true
  }
}

extension DocCSymbolLink: Hashable {
  func hash(into hasher: inout Hasher) {
    module.hash(into: &hasher)
    for component in components {
      component.asLinkComponentString.hash(into: &hasher)
    }
  }
}
