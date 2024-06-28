//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import SwiftBasicFormat
import SwiftRefactor
import SwiftSyntax

/// Convert JSON literals into corresponding Swift structs that conform to the
/// `Codable` protocol.
///
/// ## Before
///
/// ```javascript
/// {
///   "name": "Produce",
///   "shelves": [
///     {
///       "name": "Discount Produce",
///       "product": {
///         "name": "Banana",
///         "points": 200,
///         "description": "A banana that's perfectly ripe."
///       }
///     }
///   ]
/// }
/// ```
///
/// ## After
///
/// ```swift
/// struct JSONValue: Codable {
///   var name: String
///   var shelves: [Shelves]
///
///   struct Shelves: Codable {
///     var name: String
///     var product: Product
///
///     struct Product: Codable {
///       var description: String
///       var name: String
///       var points: Double
///     }
///   }
/// }
/// ```
@_spi(Testing)
public struct ConvertJSONToCodableStruct: EditRefactoringProvider {
  @_spi(Testing)
  public static func textRefactor(
    syntax: Syntax,
    in context: Void
  ) -> [SourceEdit] {
    // Dig out a syntax node that looks like it might be JSON or have JSON
    // in it.
    guard let preflight = preflightRefactoring(syntax) else {
      return []
    }

    // Dig out the text that we think might be JSON.
    let text: String
    switch preflight {
    case let .closure(closure):
      /// The outer structure of the JSON { ... } looks like a closure in the
      /// syntax tree, albeit one with lots of ill-formed syntax in the body.
      /// We're only going to look at the text of the closure to see if we
      /// have JSON in there.
      text = closure.trimmedDescription
    case let .endingClosure(closure, unexpected):
      text = closure.trimmedDescription + unexpected.description

    case .stringLiteral(_, let literalText):
      /// A string literal that could contain JSON within it.
      text = literalText
    }

    // Try to process this as JSON.
    guard
      let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else {
      return []
    }

    // Create the top-level object.
    let topLevelObject = JSONObject(dictionary: dictionary)

    // Render the top-level object as a struct.
    let indentation = BasicFormat.inferIndentation(of: syntax)
    let format = BasicFormat(indentationWidth: indentation)
    let decls = topLevelObject.asDeclSyntax(name: "JSONValue")
      .formatted(using: format)

    // Render the change into a set of source edits.
    switch preflight {
    case .closure(let closure):
      // Closures are replaced entirely, since they were invalid code to
      // start with.
      return [
        SourceEdit(range: closure.trimmedRange, replacement: decls.description)
      ]
    case .endingClosure(let closure, let unexpected):
      // Closures are replaced entirely, since they were invalid code to
      // start with.
      return [
        SourceEdit(
          range: closure.positionAfterSkippingLeadingTrivia..<unexpected.endPosition,
          replacement: decls.description
        )
      ]
    case .stringLiteral(let literal, _):
      /// Leave the string literal in place (it might be there for testing
      /// purposes), and put the newly-created structs afterward.
      return [
        SourceEdit(
          range: literal.endPosition..<literal.endPosition,
          replacement: "\n" + decls.description
        )
      ]
    }
  }

  /// The result of preflighting a syntax node to try to find potential JSON
  /// in it.
  private enum Preflight {
    /// A closure, which is what a JSON dictionary looks like when pasted
    /// into Swift.
    case closure(ClosureExprSyntax)

    /// A closure with a bunch of unexpected nodes following it, which is what
    /// a big JSON dictionary looks like when pasted into Swift.
    case endingClosure(ClosureExprSyntax, UnexpectedNodesSyntax)

    /// A string literal that may contain JSON.
    case stringLiteral(StringLiteralExprSyntax, String)
  }

  /// Look for either a closure or a string literal that might have JSON in it.
  private static func preflightRefactoring(_ syntax: Syntax) -> Preflight? {
    // Preflight a closure.
    //
    // A blob of JSON dropped into a Swift source file will look like a
    // closure due to the curly braces. The internals might be a syntactic
    // disaster, but we don't actually care.
    if let closure = syntax.as(ClosureExprSyntax.self) {
      if let file = closure.parent?.parent?.parent?.as(SourceFileSyntax.self),
        let unexpected = file.unexpectedBetweenStatementsAndEndOfFileToken
      {
        return .endingClosure(closure, unexpected)
      }
      return .closure(closure)
    }

    // We found a string literal; its contents might be JSON.
    if let stringLiteral = syntax.as(StringLiteralExprSyntax.self) {
      // Look for an enclosing context and prefer that, because we might have
      // a string literal that's inside a closure where the closure itself
      // is the JSON.
      if let parent = syntax.parent,
        let enclosingPreflight = preflightRefactoring(parent)
      {
        return enclosingPreflight
      }

      guard let text = stringLiteral.representedLiteralValue else {
        return nil
      }

      return .stringLiteral(stringLiteral, text)
    }

    // Look further up the syntax tree.
    if let parent = syntax.parent {
      return preflightRefactoring(parent)
    }

    return nil
  }
}

extension ConvertJSONToCodableStruct: SyntaxRefactoringCodeActionProvider {
  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> Syntax? {
    var node: Syntax? = scope.innermostNodeContainingRange
    while let unwrappedNode = node, ![.codeBlockItem, .memberBlockItem].contains(unwrappedNode.kind) {
      if preflightRefactoring(unwrappedNode) != nil {
        return unwrappedNode
      }
      node = unwrappedNode.parent
    }
    return nil
  }

  static let title = "Create Codable structs from JSON"
}

/// A JSON object, which is has a set of fields, each of which has the given
/// type.
fileprivate struct JSONObject {
  /// The fields of the JSON object.
  var fields: [String: JSONType] = [:]

  /// Form a JSON object from its fields.
  private init(fields: [String: JSONType]) {
    self.fields = fields
  }

  /// Form a JSON object given a dictionary.
  init(dictionary: [String: Any]) {
    fields = dictionary.mapValues { JSONType(value: $0) }
  }

  /// Merge the fields of this JSON object with another JSON object to produce
  /// a JSON object
  func merging(with other: JSONObject) -> JSONObject {
    // Collect the set of all keys from both JSON objects.
    let allKeys = Set(fields.keys).union(other.fields.keys)

    // Form a new JSON object containing the union of the fields
    let newFields = allKeys.map { key in
      let myValue = fields[key] ?? .null
      let otherValue = other.fields[key] ?? .null
      return (key, myValue.merging(with: otherValue))
    }
    return JSONObject(fields: [String: JSONType](uniqueKeysWithValues: newFields))
  }

  /// Render this JSON object into a struct.
  func asDeclSyntax(name: String) -> DeclSyntax {
    /// The list of fields in this object, sorted alphabetically.
    let sortedFields = fields.sorted(by: { $0.key < $1.key })

    // Collect the nested types
    let nestedTypes: [(name: String, type: JSONObject)] = sortedFields.compactMap { (name, type) in
      guard let object = type.innerObject else {
        return nil
      }

      return (name.capitalized, object)
    }

    let members = MemberBlockItemListSyntax {
      // Print the fields of this type.
      for (fieldName, fieldType) in sortedFields {
        MemberBlockItemSyntax(
          leadingTrivia: .newline,
          decl: "var \(raw: fieldName): \(fieldType.asTypeSyntax(name: fieldName))" as DeclSyntax
        )
      }

      // Print any nested types.
      for (typeName, object) in nestedTypes {
        MemberBlockItemSyntax(
          leadingTrivia: (typeName == nestedTypes.first?.name) ? .newlines(2) : .newline,
          decl: object.asDeclSyntax(name: typeName)
        )
      }
    }

    return """
      struct \(raw: name): Codable {
        \(members.trimmed)
      }
      """
  }
}

/// Describes the type of JSON data.
fileprivate enum JSONType {
  /// String data
  case string

  /// Numeric data
  case number

  /// Boolean data
  case boolean

  /// A "null", which implies optionality but without any underlying type
  /// information.
  case null

  /// An array.
  indirect case array(JSONType)

  /// An object.
  indirect case object(JSONObject)

  /// A value that is optional, for example because it is missing or null in
  /// other cases.
  indirect case optional(JSONType)

  /// Determine the type of a JSON value.
  init(value: Any) {
    switch value {
    case let string as String:
      switch string {
      case "true", "false": self = .boolean
      default: self = .string
      }
    case is NSNumber:
      self = .number
    case let array as [Any]:
      // Use null as a fallback for an empty array.
      guard let firstValue = array.first else {
        self = .array(.null)
        return
      }

      // Merge the array elements.
      let elementType: JSONType = array[1...].reduce(
        JSONType(value: firstValue)
      ) { (result, value) in
        result.merging(with: JSONType(value: value))
      }
      self = .array(elementType)

    case is NSNull:
      self = .null
    case let dictionary as [String: Any]:
      self = .object(JSONObject(dictionary: dictionary))
    default:
      self = .string
    }
  }

  /// Merge this JSON type with another JSON type, producing a new JSON type
  /// that abstracts over the two.
  func merging(with other: JSONType) -> JSONType {
    switch (self, other) {
    // Exact matches are easy.
    case (.string, .string): return .string
    case (.number, .number): return .number
    case (.boolean, .boolean): return .boolean
    case (.null, .null): return .null

    case (.array(let inner), .array(.null)), (.array(.null), .array(let inner)):
      // Merging an array with an array of null leaves the array.
      return .array(inner)

    case (.array(let inner), .null), (.null, .array(let inner)):
      // Merging an array with a null just leaves an array.
      return .array(inner)

    case (.array(let left), .array(let right)):
      // Merging two arrays merges the element types
      return .array(left.merging(with: right))

    case (.object(let left), .object(let right)):
      // Merging two arrays merges the element types
      return .object(left.merging(with: right))

    // Merging a string with a Boolean means we misinterpreted "true" or
    // "false" as Boolean when it was meant as a string.
    case (.string, .boolean), (.boolean, .string): return .string

    // Merging 'null' with an optional returns the optional.
    case (.optional(let inner), .null), (.null, .optional(let inner)):
      return .optional(inner)

    // Merging 'null' with anything else makes it an optional.
    case (let inner, .null), (.null, let inner):
      return .optional(inner)

    // Merging two optionals merges the underlying types and makes the
    // result optional.
    case (.optional(let left), .optional(let right)):
      return .optional(left.merging(with: right))

    // Merging an optional with anything else merges the underlying bits and
    // makes them optional.
    case (let outer, .optional(let inner)), (.optional(let inner), let outer):
      return .optional(inner.merging(with: outer))

    // Fall back to the null case when we don't know.
    default:
      return .null
    }
  }

  /// Dig out the JSON inner object referenced by this type.
  var innerObject: JSONObject? {
    switch self {
    case .string, .null, .number, .boolean: nil
    case .optional(let inner): inner.innerObject
    case .array(let inner): inner.innerObject
    case .object(let object): object
    }
  }

  /// Render this JSON type into type syntax.
  func asTypeSyntax(name: String) -> TypeSyntax {
    switch self {
    case .string: "String"
    case .number: "Double"
    case .boolean: "Bool"
    case .null: "Void"
    case .optional(let inner): "\(inner.asTypeSyntax(name: name))?"
    case .array(let inner): "[\(inner.asTypeSyntax(name: name))]"
    case .object(_): "\(raw: name.capitalized)"
    }
  }
}
