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

  struct Object {
    var name: String
    /// Properties of the object, preserving the order of declaration
    var properties: [Property]
  }

  struct Case {
    var name: String
    var description: String?
  }

  struct Enum {
    var name: String
    var cases: [Case]
  }

  enum Kind {
    case boolean
    case integer
    case number
    case string
    indirect case array(value: OptionTypeSchama)
    indirect case dictionary(value: OptionTypeSchama)
    case object(Object)
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
      guard case .object(let object) = kind else {
        return nil
      }
      return object.properties.first { $0.name == key }?.type
    }
    set {
      guard case .object(var object) = kind else {
        fatalError("Cannot set property on non-object type")
      }
      guard let index = object.properties.firstIndex(where: { $0.name == key }) else {
        fatalError("Property not found: \(key)")
      }
      guard let newValue = newValue else {
        fatalError("Cannot set property to nil")
      }
      object.properties[index].type = newValue
      kind = .object(object)
    }
  }
}

/// Context for resolving option schema from Swift syntax nodes
struct OptionSchemaContext {
  let typeNameResolver: TypeDeclResolver

  /// Builds a schema from a type declaration
  func buildSchema(from typeDecl: TypeDeclResolver.TypeDecl) throws -> OptionTypeSchama {
    switch DeclSyntax(typeDecl).as(DeclSyntaxEnum.self) {
    case .structDecl(let decl):
      let structInfo = try buildStructProperties(decl)
      return OptionTypeSchama(kind: .object(structInfo))
    case .enumDecl(let decl):
      let enumInfo = buildEnumCases(decl)
      return OptionTypeSchama(kind: .enum(enumInfo))
    default:
      fatalError("Unsupported type: \(typeDecl)")
    }
  }

  /// Resolves the type of a given type usage
  private func resolveType(_ type: TypeSyntax) throws -> OptionTypeSchama {
    switch type.as(TypeSyntaxEnum.self) {
    case .optionalType(let type):
      var wrapped = try resolveType(type.wrappedType)
      assert(!wrapped.isOptional, "Nested optional type is not supported")
      wrapped.isOptional = true
      return wrapped
    case .arrayType(let type):
      let value = try resolveType(type.element)
      return OptionTypeSchama(kind: .array(value: value))
    case .dictionaryType(let type):
      guard type.key.trimmedDescription == "String" else {
        fatalError("Dictionary key type must be String: \(type.key)")
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
          fatalError("Set type must have one generic argument: \(type)")
        }
        return OptionTypeSchama(kind: .array(value: try resolveType(elementType)))
      } else {
        let type = try typeNameResolver.lookupType(for: type)
        return try buildSchema(from: type)
      }
    default:
      fatalError("Unsupported type: \(type)")
    }
  }

  private func buildEnumCases(_ node: EnumDeclSyntax) -> OptionTypeSchama.Enum {
    let cases = node.memberBlock.members.flatMap { member -> [OptionTypeSchama.Case] in
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else {
        return []
      }
      return caseDecl.elements.map {
        guard $0.parameterClause == nil else {
          fatalError("Associated values are not supported: \($0)")
        }
        let name: String
        if let rawValue = $0.rawValue?.value {
          if let stringLiteral = rawValue.as(StringLiteralExprSyntax.self), stringLiteral.segments.count == 1 {
            name = stringLiteral.segments.first!.description
          } else {
            fatalError("Unsupported raw value type: \(rawValue)")
          }
        } else {
          name = $0.name.text
        }
        return OptionTypeSchama.Case(name: name, description: Self.extractDocComment(caseDecl.leadingTrivia))
      }
    }
    let typeName = node.name.text
    return .init(name: typeName, cases: cases)
  }

  private func buildStructProperties(_ node: StructDeclSyntax) throws -> OptionTypeSchama.Object {
    var properties: [OptionTypeSchama.Property] = []
    for member in node.memberBlock.members {
      // Skip computed properties
      if let variable = member.decl.as(VariableDeclSyntax.self),
        let binding = variable.bindings.first,
        let type = binding.typeAnnotation,
        binding.accessorBlock == nil
      {
        let name = binding.pattern.trimmed.description
        let defaultValue = binding.initializer?.value.description
        let description = Self.extractDocComment(variable.leadingTrivia)
        let typeInfo = try resolveType(type.type)
        properties.append(
          .init(name: name, type: typeInfo, description: description, defaultValue: defaultValue)
        )
      }
    }
    let typeName = node.name.text
    return .init(name: typeName, properties: properties)
  }

  private static func extractDocComment(_ trivia: Trivia) -> String? {
    let docContents = trivia.compactMap { piece in
      switch piece {
      case .docBlockComment(let text):
        // Remove `/**` and `*/`
        assert(text.hasPrefix("/**") && text.hasSuffix("*/"), "Unexpected doc block comment format: \(text)")
        return String(text.dropFirst(3).dropLast(2))
      case .docLineComment(let text):
        // Remove `///` and leading space
        assert(text.hasPrefix("///"), "Unexpected doc line comment format: \(text)")
        var text = text.dropFirst(3)
        while text.first?.isWhitespace == true {
          text = text.dropFirst()
        }
        return String(text)
      default:
        return nil
      }
    }
    guard !docContents.isEmpty else {
      return nil
    }
    return docContents.joined(separator: "\n")
  }
}
