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

/// A completion kind.
///
/// In LSP, this is an integer, so we don't use a closed set.
public struct CompletionItemKind: RawRepresentable, Codable, Hashable {

  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  // MARK: LSP completion kinds

  // LSP 1 kinds, guaranteed to be supported by all clients.
  public static let text: CompletionItemKind = CompletionItemKind(rawValue: 1)
  public static let method: CompletionItemKind = CompletionItemKind(rawValue: 2)
  public static let function: CompletionItemKind = CompletionItemKind(rawValue: 3)
  public static let constructor: CompletionItemKind = CompletionItemKind(rawValue: 4)
  public static let field: CompletionItemKind = CompletionItemKind(rawValue: 5)
  public static let variable: CompletionItemKind = CompletionItemKind(rawValue: 6)
  public static let `class`: CompletionItemKind = CompletionItemKind(rawValue: 7)
  public static let interface: CompletionItemKind = CompletionItemKind(rawValue: 8)
  public static let module: CompletionItemKind = CompletionItemKind(rawValue: 9)
  public static let property: CompletionItemKind = CompletionItemKind(rawValue: 10)
  public static let unit: CompletionItemKind = CompletionItemKind(rawValue: 11)
  public static let value: CompletionItemKind = CompletionItemKind(rawValue: 12)
  public static let `enum`: CompletionItemKind = CompletionItemKind(rawValue: 13)
  public static let keyword: CompletionItemKind = CompletionItemKind(rawValue: 14)
  public static let snippet: CompletionItemKind = CompletionItemKind(rawValue: 15)
  public static let color: CompletionItemKind = CompletionItemKind(rawValue: 16)
  public static let file: CompletionItemKind = CompletionItemKind(rawValue: 17)
  public static let reference: CompletionItemKind = CompletionItemKind(rawValue: 18)

  // LSP 3+
  public static let folder: CompletionItemKind = CompletionItemKind(rawValue: 19)
  public static let enumMember: CompletionItemKind = CompletionItemKind(rawValue: 20)
  public static let constant: CompletionItemKind = CompletionItemKind(rawValue: 21)
  public static let `struct`: CompletionItemKind = CompletionItemKind(rawValue: 22)
  public static let event: CompletionItemKind = CompletionItemKind(rawValue: 23)
  public static let `operator`: CompletionItemKind = CompletionItemKind(rawValue: 24)
  public static let typeParameter: CompletionItemKind = CompletionItemKind(rawValue: 25)
}
