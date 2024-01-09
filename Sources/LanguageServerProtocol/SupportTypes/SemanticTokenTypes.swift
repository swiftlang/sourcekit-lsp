//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// The predefined token type values
///
/// The protocol defines a set of token types and modifiers but clients are
/// allowed to extend these and announce the values they support in the
/// corresponding client capability.
public struct SemanticTokenTypes: Hashable {
  public let name: String
  public init(_ name: String) {
    self.name = name
  }

  public static let namespace = Self("namespace")
  /// Represents a generic type. Acts as a fallback for types which
  /// can't be mapped to a specific type like class or enum.
  public static let type = Self("type")
  public static let `class` = Self("class")
  public static let `enum` = Self("enum")
  public static let interface = Self("interface")
  public static let `struct` = Self("struct")
  public static let typeParameter = Self("typeParameter")
  public static let parameter = Self("parameter")
  public static let variable = Self("variable")
  public static let property = Self("property")
  public static let enumMember = Self("enumMember")
  public static let event = Self("event")
  public static let function = Self("function")
  public static let method = Self("method")
  public static let macro = Self("macro")
  public static let keyword = Self("keyword")
  public static let modifier = Self("modifier")
  public static let comment = Self("comment")
  public static let string = Self("string")
  public static let number = Self("number")
  public static let regexp = Self("regexp")
  public static let `operator` = Self("operator")
  /// since 3.17.0
  public static let decorator = Self("decorator")

  public static var predefined: [Self] = [
    .namespace,
    .type,
    .class,
    .enum,
    .interface,
    .struct,
    .typeParameter,
    .parameter,
    .variable,
    .property,
    .enumMember,
    .event,
    .function,
    .method,
    .macro,
    .keyword,
    .modifier,
    .comment,
    .string,
    .number,
    .regexp,
    .operator,
  ]
}
