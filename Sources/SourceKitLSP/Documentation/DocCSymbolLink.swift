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

#if canImport(SwiftDocC)
import Foundation
@preconcurrency import SwiftDocC

/// Represents the link to a symbol in DocC documentation.
///
/// Symbol links are always of the form `<ModuleName>/<SymbolName>` or simply `<ModuleName>`
/// if they refer to the module itself.
struct DocCSymbolLink: Sendable {
  let moduleName: String
  let components: [AbsoluteSymbolLink.LinkComponent]

  var absoluteString: String {
    return components.map { $0.asLinkComponentString }.joined(separator: "/")
  }

  var representsModule: Bool {
    return components.count == 1
  }

  init(absoluteSymbolLink: AbsoluteSymbolLink) {
    self.moduleName = absoluteSymbolLink.module
    guard !absoluteSymbolLink.representsModule else {
      self.components = []
      return
    }
    self.components = [absoluteSymbolLink.topLevelSymbol] + absoluteSymbolLink.basePathComponents
  }

  init?(string: String) {
    var rawComponents = string.split(separator: "/")
    guard rawComponents.count > 0 else {
      return nil
    }
    let moduleName = String(rawComponents.removeFirst())
    var components = [AbsoluteSymbolLink.LinkComponent]()
    for rawComponent in rawComponents {
      guard let component = AbsoluteSymbolLink.LinkComponent(string: String(rawComponent)) else {
        return nil
      }
      components.append(component)
    }
    self = DocCSymbolLink(moduleName: moduleName, components: components)
  }

  private init(moduleName: String, components: [AbsoluteSymbolLink.LinkComponent]) {
    self.moduleName = moduleName
    self.components = components
  }

  func appending(string componentString: String) -> DocCSymbolLink? {
    guard let component = AbsoluteSymbolLink.LinkComponent(string: componentString) else {
      return nil
    }
    return DocCSymbolLink(moduleName: moduleName, components: components + [component])
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
    guard lhs.components.count == rhs.components.count else {
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
    for component in components {
      component.asLinkComponentString.hash(into: &hasher)
    }
  }
}
#endif
