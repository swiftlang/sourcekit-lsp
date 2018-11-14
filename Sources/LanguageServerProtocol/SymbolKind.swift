//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A symbol kind.
///
/// In LSP, this is an integer, so we don't use a closed set.
public struct SymbolKind: RawRepresentable, Codable, Hashable {

  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  // MARK: LSP symbol kinds

  // LSP 1 kinds, guaranteed to be supported by all clients.
  public static let file = SymbolKind(rawValue: 1)
  public static let module = SymbolKind(rawValue: 2)
  public static let namespace = SymbolKind(rawValue: 3)
  public static let package = SymbolKind(rawValue: 4)
  public static let `class` = SymbolKind(rawValue: 5)
  public static let method = SymbolKind(rawValue: 6)
  public static let property = SymbolKind(rawValue: 7)
  public static let field = SymbolKind(rawValue: 8)
  public static let constructor = SymbolKind(rawValue: 9)
  public static let `enum` = SymbolKind(rawValue: 10)
  public static let interface = SymbolKind(rawValue: 11)
  public static let function = SymbolKind(rawValue: 12)
  public static let variable = SymbolKind(rawValue: 13)
  public static let constant = SymbolKind(rawValue: 14)
  public static let string = SymbolKind(rawValue: 15)
  public static let number = SymbolKind(rawValue: 16)
  public static let boolean = SymbolKind(rawValue: 17)
  public static let array = SymbolKind(rawValue: 18)

  // LSP 3+
  public static let object = SymbolKind(rawValue: 19)
  public static let key = SymbolKind(rawValue: 20)
  public static let null = SymbolKind(rawValue: 21)
  public static let enumMember = SymbolKind(rawValue: 22)
  public static let `struct` = SymbolKind(rawValue: 23)
  public static let event = SymbolKind(rawValue: 24)
  public static let `operator` = SymbolKind(rawValue: 25)
  public static let typeParameter = SymbolKind(rawValue: 26)
}
