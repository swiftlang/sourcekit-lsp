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
import SwiftRefactor
import SwiftSyntax

/// Convert JSON literals into corresponding Swift structs that conform to the
/// `Codable` protocol.
///
/// ## Before
///
/// ```javascript
/// {
///     "name": "Produce",
///     "shelves": [
///         {
///             "name": "Discount Produce",
///             "product": {
///                 "name": "Banana",
///                 "points": 200,
///                 "description": "A banana that's perfectly ripe."
///             }
///         }
///     ]
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
public struct ConvertJSONToCodableStructRefactor: SyntaxRefactoringProvider {
  public static func refactor(syntax closure: ClosureExprSyntax, in context: Void) -> DeclSyntax? {
    guard let unexpected = self.preflightRefactoring(closure) else {
      return nil
    }

    var text = ""
    switch unexpected {
    case let .closure(closure):
      closure.write(to: &text)
    case let .tail(closure, unexpected):
      closure.write(to: &text)
      unexpected.write(to: &text)
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: text.data(using: .utf8)!),
      let serial = object as? Dictionary<String, Any>
    else {
      return nil
    }

    return self.build(from: serial)
  }
}

extension ConvertJSONToCodableStructRefactor {
  public enum Preflight {
    case closure(ClosureExprSyntax)
    case tail(ClosureExprSyntax, UnexpectedNodesSyntax)
  }
  public static func preflightRefactoring(_ closure: ClosureExprSyntax) -> Preflight? {
    if let file = closure.parent?.parent?.parent?.as(SourceFileSyntax.self),
      let unexpected = file.unexpectedBetweenStatementsAndEndOfFileToken
    {
      return .tail(closure, unexpected)
    }

    if closure.hasError,
      closure.unexpectedBetweenStatementsAndRightBrace != nil
    {
      return .closure(closure)
    }
    return nil
  }
}

extension ConvertJSONToCodableStructRefactor {
  private static func build(from jsonDictionary: Dictionary<String, Any>) -> DeclSyntax {
    return
      """
      \(raw: self.buildStruct(from: jsonDictionary))
      """
  }

  private static func buildStruct(
    named name: String = "JSONValue",
    at depth: Int = 0,
    from jsonDictionary: Dictionary<String, Any>
  ) -> String {
    let members = self.buildStructMembers(at: depth + 1, from: jsonDictionary)
    return
      """
      \(String(repeating: " ", count: depth * 2))struct \(name): Codable {
      \(members.joined(separator: "\n"))
      \(String(repeating: " ", count: depth * 2))}
      """
  }

  private static func buildStructMembers(
    at depth: Int,
    from jsonDictionary: Dictionary<String, Any>
  ) -> [String] {
    var members = [String]()

    var uniquer = Set<String>()
    var nestedTypes = [(String, Dictionary<String, Any>)]()
    func addNestedType(_ name: String, object: Dictionary<String, Any>) {
      guard uniquer.insert(name).inserted else {
        return
      }
      nestedTypes.append((name, object))
    }

    for key in jsonDictionary.keys.sorted() {
      guard let value = jsonDictionary[key] else {
        continue
      }

      let type = self.jsonType(of: value, suggestion: key)
      if case let .object(name) = type, let subObject = value as? Dictionary<String, Any> {
        addNestedType(name, object: subObject)
      } else if case let .array(innerType) = type,
        let array = value as? [Any],
        let (nesting, elementType) = innerType.outermostObject
      {
        if let subObject = array.unwrap(nesting) {
          addNestedType(elementType, object: subObject)
        }
      }

      let member = "\(String(repeating: " ", count: depth * 2))var \(key): \(type.stringValue)"
      members.append(member)
    }

    if !nestedTypes.isEmpty {
      members.append("")
      for (name, nestedType) in nestedTypes {
        members.append(self.buildStruct(named: name, at: depth, from: nestedType))
      }
    }
    return members
  }

  indirect enum JSONType {
    case string
    case double
    case array(JSONType)
    case null
    case object(String)

    var outermostObject: (Int, String)? {
      var unwraps = 1
      var value = self
      while case let .array(inner) = value {
        value = inner
        unwraps += 1
      }

      if case let .object(typeName) = value {
        return (unwraps, typeName)
      } else {
        return nil
      }
    }

    var stringValue: String {
      switch self {
      case .string:
        return "String"
      case .double:
        return "Double"
      case .array(let ty):
        return "[\(ty.stringValue)]"
      case .null:
        return "Void?"
      case let .object(name):
        return name
      }
    }
  }

  private static func jsonType(of value: Any, suggestion name: String) -> JSONType {
    switch Swift.type(of: value) {
    case is NSString.Type:
      return .string
    case is NSNumber.Type:
      return .double
    case is NSArray.Type:
      guard let firstValue = (value as! [Any]).first else {
        return .array(.null)
      }
      let innerType = self.jsonType(of: firstValue, suggestion: name)
      return .array(innerType)
    case is NSNull.Type:
      return .null
    case is NSDictionary.Type:
      return .object(name.capitalized)
    default:
      return .string
    }
  }
}

extension Array where Element == Any {
  fileprivate func unwrap(_ depth: Int) -> Dictionary<String, Any>? {
    var values: [Any] = self
    for i in 0..<depth {
      if i + 1 == depth {
        return values[0] as? Dictionary<String, Any>
      }

      guard let moreValues = values[0] as? [Any] else {
        return nil
      }

      values = moreValues
    }
    return nil
  }
}

public struct ConvertJSONToCodableStruct: CodeActionProvider {
  public static var kind: CodeActionKind { .refactorRewrite }

  public static func provideAssistance(in scope: CodeActionScope) -> [ProvidedAction] {
    guard
      let token = scope.file.token(at: scope.range.offset),
      let closure = token.parent?.as(ClosureExprSyntax.self),
      closure.hasError
    else {
      return []
    }

    guard let preflight = ConvertJSONToCodableStructRefactor.preflightRefactoring(closure) else {
      return []
    }

    guard
      let decl = ConvertJSONToCodableStructRefactor.refactor(syntax: closure)
    else {
      return []
    }

    switch preflight {
    case .closure(let closure):
      return [
        ProvidedAction(title: "Convert to Codable struct") {
          Replace(closure, with: decl)
        }
      ]
    case .tail(let closure, let unexpected):
      return [
        ProvidedAction(title: "Convert to Codable struct") {
          Replace(closure, with: decl)
          Remove(unexpected)
        }
      ]
    }
  }
}
