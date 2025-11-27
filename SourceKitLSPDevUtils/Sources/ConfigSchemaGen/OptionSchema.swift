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

import SwiftSyntax

/// Intermediate type schema representation for option types derived from Swift
/// syntax nodes
struct OptionTypeSchama {
  struct Property {
    var name: String
    var type: OptionTypeSchama
    var description: String?
    var defaultValue: String?
  }

  struct Struct {
    var name: String
    /// Properties of the object, preserving the order of declaration
    var properties: [Property]
  }

  struct Case {
    var name: String
    var description: String?
    var associatedProperties: [Property]?
  }

  struct Enum {
    var name: String
    var cases: [Case]
    var discriminatorFieldName: String?
  }

  enum Kind {
    case boolean
    case integer
    case number
    case string
    indirect case array(value: OptionTypeSchama)
    indirect case dictionary(value: OptionTypeSchama)
    case `struct`(Struct)
    case `enum`(Enum)
  }

  var kind: Kind
  var isOptional: Bool

  init(kind: Kind, isOptional: Bool = false) {
    self.kind = kind
    self.isOptional = isOptional
  }

  /// Accesses the property schema by name
  subscript(_ key: String) -> OptionTypeSchama? {
    get {
      guard case .struct(let structInfo) = kind else {
        return nil
      }
      return structInfo.properties.first { $0.name == key }?.type
    }
    set {
      guard case .struct(var structInfo) = kind else {
        fatalError("Cannot set property on non-object type")
      }
      guard let index = structInfo.properties.firstIndex(where: { $0.name == key }) else {
        fatalError("Property not found: \(key)")
      }
      guard let newValue = newValue else {
        fatalError("Cannot set property to nil")
      }
      structInfo.properties[index].type = newValue
      kind = .struct(structInfo)
    }
  }
}

/// Context for resolving option schema from Swift syntax nodes
struct OptionSchemaContext {
  private let typeNameResolver: TypeDeclResolver

  init(typeNameResolver: TypeDeclResolver) {
    self.typeNameResolver = typeNameResolver
  }

  /// Builds a schema from a type declaration
  func buildSchema(from typeDecl: TypeDeclResolver.TypeDecl) throws -> OptionTypeSchama {
    switch DeclSyntax(typeDecl).as(DeclSyntaxEnum.self) {
    case .structDecl(let decl):
      let structInfo = try buildStructProperties(decl)
      return OptionTypeSchama(kind: .struct(structInfo))
    case .enumDecl(let decl):
      let enumInfo = try buildEnumCases(decl)
      return OptionTypeSchama(kind: .enum(enumInfo))
    default:
      throw ConfigSchemaGenError("Unsupported type declaration: \(typeDecl)")
    }
  }

  /// Resolves the type of a given type usage
  private func resolveType(_ type: TypeSyntax) throws -> OptionTypeSchama {
    switch type.as(TypeSyntaxEnum.self) {
    case .optionalType(let type):
      var wrapped = try resolveType(type.wrappedType)
      guard !wrapped.isOptional else {
        throw ConfigSchemaGenError("Nested optional type is not supported")
      }
      wrapped.isOptional = true
      return wrapped
    case .arrayType(let type):
      let value = try resolveType(type.element)
      return OptionTypeSchama(kind: .array(value: value))
    case .dictionaryType(let type):
      guard type.key.trimmedDescription == "String" else {
        throw ConfigSchemaGenError("Dictionary key type must be String: \(type.key)")
      }
      let value = try resolveType(type.value)
      return OptionTypeSchama(kind: .dictionary(value: value))
    case .identifierType(let type):
      let primitiveTypes: [String: OptionTypeSchama.Kind] = [
        "String": .string,
        "Int": .integer,
        "Double": .number,
        "Bool": .boolean,
      ]
      if let primitiveType = primitiveTypes[type.trimmedDescription] {
        return OptionTypeSchama(kind: primitiveType)
      } else if type.name.trimmedDescription == "Set" {
        guard let elementType = type.genericArgumentClause?.arguments.first?.argument else {
          throw ConfigSchemaGenError("Set type must have one generic argument: \(type)")
        }
        return OptionTypeSchama(kind: .array(value: try resolveType(elementType)))
      } else {
        let type = try typeNameResolver.lookupType(for: type)
        return try buildSchema(from: type)
      }
    default:
      throw ConfigSchemaGenError("Unsupported type syntax: \(type)")
    }
  }

  private func buildEnumCases(_ node: EnumDeclSyntax) throws -> OptionTypeSchama.Enum {
    let discriminatorFieldName = Self.extractDiscriminatorFieldName(node.leadingTrivia)

    let cases = try node.memberBlock.members.flatMap { member -> [OptionTypeSchama.Case] in
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else {
        return []
      }
      return try caseDecl.elements.compactMap {
        let name: String
        if let rawValue = $0.rawValue?.value {
          if let stringLiteral = rawValue.as(StringLiteralExprSyntax.self),
            let literalValue = stringLiteral.representedLiteralValue
          {
            name = literalValue
          } else {
            throw ConfigSchemaGenError(
              "Only string literals without interpolation are supported as enum case raw values: \(caseDecl)"
            )
          }
        } else {
          name = $0.name.text
        }
        let description = Self.extractDocComment(caseDecl.leadingTrivia)
        if description?.contains("- Note: Internal option") ?? false {
          return nil
        }

        var associatedProperties: [OptionTypeSchama.Property]? = nil
        if let parameterClause = $0.parameterClause {
          let caseDescription = description
          associatedProperties = try parameterClause.parameters.map { param in
            let propertyName: String
            if let firstName = param.firstName, firstName.tokenKind != .wildcard {
              propertyName = firstName.text
            } else if let secondName = param.secondName {
              propertyName = secondName.text
            } else {
              propertyName = name
            }

            let propertyType = try resolveType(param.type)
            let propertyDescription =
              Self.extractParameterDescription(
                from: caseDescription,
                parameterName: propertyName
              ) ?? Self.extractDocComment(param.leadingTrivia)

            return OptionTypeSchama.Property(
              name: propertyName,
              type: propertyType,
              description: propertyDescription,
              defaultValue: nil
            )
          }
        }

        return OptionTypeSchama.Case(
          name: name,
          description: description,
          associatedProperties: associatedProperties
        )
      }
    }
    let typeName = node.name.text
    return .init(name: typeName, cases: cases, discriminatorFieldName: discriminatorFieldName)
  }

  private func buildStructProperties(_ node: StructDeclSyntax) throws -> OptionTypeSchama.Struct {
    var properties: [OptionTypeSchama.Property] = []
    for member in node.memberBlock.members {
      // Skip computed properties
      guard let variable = member.decl.as(VariableDeclSyntax.self),
        let binding = variable.bindings.first,
        let type = binding.typeAnnotation,
        binding.accessorBlock == nil
      else { continue }

      let name = binding.pattern.trimmed.description
      let defaultValue = binding.initializer?.value.description
      let description = Self.extractDocComment(variable.leadingTrivia)
      if description?.contains("- Note: Internal option") ?? false {
        continue
      }
      let typeInfo = try resolveType(type.type)
      properties.append(
        .init(name: name, type: typeInfo, description: description, defaultValue: defaultValue)
      )
    }
    let typeName = node.name.text
    return .init(name: typeName, properties: properties)
  }

  private static func extractDocComment(_ trivia: Trivia) -> String? {
    var docLines = trivia.flatMap { piece in
      switch piece {
      case .docBlockComment(let text):
        // Remove `/**` and `*/`
        assert(text.hasPrefix("/**") && text.hasSuffix("*/"), "Unexpected doc block comment format: \(text)")
        return text.dropFirst(3).dropLast(2).split { $0.isNewline }
      case .docLineComment(let text):
        // Remove `///` and leading space
        assert(text.hasPrefix("///"), "Unexpected doc line comment format: \(text)")
        let text = text.dropFirst(3)
        return [text]
      default:
        return []
      }
    }
    guard !docLines.isEmpty else {
      return nil
    }
    // Trim leading spaces for each line and skip empty lines
    docLines = docLines.compactMap {
      guard !$0.isEmpty else { return nil }
      var trimmed = $0
      while trimmed.first?.isWhitespace == true {
        trimmed = trimmed.dropFirst()
      }
      return trimmed
    }
    return docLines.joined(separator: " ")
  }

  private static func extractDiscriminatorFieldName(_ trivia: Trivia) -> String? {
    let docLines = trivia.flatMap { piece -> [Substring] in
      switch piece {
      case .docBlockComment(let text):
        assert(text.hasPrefix("/**") && text.hasSuffix("*/"), "Unexpected doc block comment format: \(text)")
        return text.dropFirst(3).dropLast(2).split { $0.isNewline }
      case .docLineComment(let text):
        assert(text.hasPrefix("///"), "Unexpected doc line comment format: \(text)")
        let text = text.dropFirst(3)
        return [text]
      default:
        return []
      }
    }

    for line in docLines {
      let trimmed = line.drop(while: \.isWhitespace)
      if trimmed.hasPrefix("- discriminator:") {
        let fieldName = trimmed.dropFirst("- discriminator:".count).trimmingCharacters(in: .whitespaces)
        return fieldName.isEmpty ? nil : fieldName
      }
    }
    return nil
  }

  private static func extractParameterDescription(from docComment: String?, parameterName: String) -> String? {
    guard let docComment = docComment else {
      return nil
    }

    let pattern = "`\(parameterName)`:"
    guard let range = docComment.range(of: pattern) else {
      return nil
    }

    let afterPattern = docComment[range.upperBound...]
    let lines = afterPattern.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    guard let firstLine = lines.first else {
      return nil
    }

    let description = firstLine.trimmingCharacters(in: .whitespaces)
    return description.isEmpty ? nil : description
  }
}
