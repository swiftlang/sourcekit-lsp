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

package import LanguageServerProtocol
import SourceKitLSP
import SwiftBasicFormat
import SwiftRefactor
package import SwiftSyntax
import SwiftSyntaxBuilder
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

/// Generates a memberwise initializer for a struct, class or actor.
///
/// ## Before
///
/// ```swift
/// struct Place {
///   let street: String
///   var floor = 3
/// }
/// ```
///
/// ## After
///
/// ```swift
/// struct Place {
///   internal init(street: String, floor: Int = 3) {
///     self.street = street
///     self.floor = floor
///   }
///
///   let street: String
///   var floor = 3
/// }
/// ```
///
/// The type of `floor` isn't spelled out in the source, so it is looked up using sourcekitd in the `codeAction/resolve`
/// request. If the client doesn't support resolving code actions, a `<#Type#>` placeholder is inserted instead.
package struct GenerateMemberwiseInitializer: ResolvableSyntaxRefactoringCodeActionProvider {
  package typealias Input = DeclSyntax

  static let title: String = "Generate Memberwise Initializer"

  package struct Context {
    /// Keyed by property name.
    package let types: [String: TypeSyntax]

    package init(types: [String: TypeSyntax] = [:]) {
      self.types = types
    }
  }

  package struct UnresolvedData: Codable, LSPAnyCodable {
    package struct Property: Codable {
      package let name: String
      package let position: Position
    }

    package let properties: [Property]
  }

  static func nodeToRefactor(in scope: SyntaxCodeActionScope) -> DeclSyntax? {
    // Only offer the refactoring on the type's header, not inside its body.
    let decl = scope.innermostNodeContainingRange?.findParentOfSelf(
      ofType: DeclSyntax.self,
      stoppingIf: { $0.is(CodeBlockSyntax.self) || $0.is(MemberBlockSyntax.self) },
      matching: { $0.is(StructDeclSyntax.self) || $0.is(ClassDeclSyntax.self) || $0.is(ActorDeclSyntax.self) }
    )
    guard let decl, let declGroup = decl.asProtocol((any DeclGroupSyntax).self),
      !storedProperties(of: declGroup).isEmpty
    else {
      return nil
    }
    return decl
  }

  static func refactoringContext(
    for node: DeclSyntax,
    in scope: SyntaxCodeActionScope
  ) -> RefactoringContext<Context, UnresolvedData> {
    guard scope.resolveSupport?.canResolveEdit ?? false,
      let declGroup = node.asProtocol((any DeclGroupSyntax).self)
    else {
      // Without resolve support, fall back to placeholders for the types we can't determine syntactically.
      return .context(Context())
    }
    let unresolvedProperties = storedProperties(of: declGroup).filter { $0.type == nil }.map { property in
      UnresolvedData.Property(
        name: property.name,
        position: scope.snapshot.position(of: property.identifier.positionAfterSkippingLeadingTrivia)
      )
    }
    guard !unresolvedProperties.isEmpty else {
      // All types are spelled out, nothing to resolve.
      return .context(Context())
    }
    return .unresolved(UnresolvedData(properties: unresolvedProperties))
  }

  static func resolveContext(
    for data: UnresolvedData,
    in scope: SyntaxCodeActionScope,
    symbolInfo: (_ position: Position) async throws -> [SymbolDetails]
  ) async throws -> Context {
    var types: [String: TypeSyntax] = [:]
    for property in data.properties {
      guard let typeName = try await symbolInfo(property.position).only?.typeName, typeName != "_" else {
        continue
      }
      types[property.name] = "\(raw: typeName)"
    }
    return Context(types: types)
  }

  package static func textRefactor(syntax: DeclSyntax, in context: Context) throws -> [SourceEdit] {
    guard let declGroup = syntax.asProtocol((any DeclGroupSyntax).self) else {
      throw RefactoringNotApplicableError("not a type declaration")
    }
    let properties = storedProperties(of: declGroup)
    guard !properties.isEmpty else {
      throw RefactoringNotApplicableError("type has no stored properties")
    }

    let (memberIndentation, bodyIndentation) = indentation(of: declGroup)

    let parameters = properties.map { property -> String in
      let type = property.type ?? context.types[property.name]
      var parameter = "\(property.name): \(type.map(parameterType(for:)) ?? "<#Type#>")"
      if let defaultValue = property.defaultValue {
        parameter += " = \(defaultValue)"
      } else if type?.isOptional ?? false {
        parameter += " = nil"
      }
      return parameter
    }
    let assignments = properties.map { "\(bodyIndentation)self.\($0.name) = \($0.name)" }

    let initializer = """
      \(memberIndentation)internal init(\(parameters.joined(separator: ", "))) {
      \(assignments.joined(separator: "\n"))
      \(memberIndentation)}

      """
    // The first member keeps its leading newline, which leaves an empty line after the initializer.
    let position = declGroup.memberBlock.leftBrace.endPosition
    return [SourceEdit(range: position..<position, replacement: "\n" + initializer)]
  }

  struct StoredProperty {
    let identifier: TokenSyntax

    /// Includes backticks, if the name is escaped in source.
    var name: String { identifier.text }

    /// For `var a, b: Int`, this is `Int` for both `a` and `b`.
    let type: TypeSyntax?

    let defaultValue: String?
  }

  /// The stored properties that get a parameter in the memberwise initializer, in declaration order.
  ///
  /// Unlike the compiler, this includes `private` properties. It's easier to delete a parameter than to add one.
  static func storedProperties(of decl: some DeclGroupSyntax) -> [StoredProperty] {
    var properties: [StoredProperty] = []
    // Properties that are initialized through another property's `init` accessor don't get their own parameter.
    var initializedByInitAccessor: Set<String> = []

    for member in decl.memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else {
        continue
      }
      let hasExcludedModifier = variable.modifiers.contains { modifier in
        switch modifier.name.tokenKind {
        case .keyword(.static), .keyword(.class), .keyword(.lazy):
          // There's no way to initialize the storage of a `lazy` property from an initializer.
          return true
        default:
          return false
        }
      }
      if hasExcludedModifier {
        continue
      }
      let isLet = variable.bindingSpecifier.tokenKind == .keyword(.let)
      let bindings = Array(variable.bindings)
      for (index, binding) in bindings.enumerated() {
        if let accessorBlock = binding.accessorBlock {
          switch accessorBlock.accessors {
          case .getter:
            continue
          case .accessors(let accessors):
            if let initAccessor = accessors.first(where: { $0.accessorSpecifier.tokenKind == .keyword(.`init`) }) {
              // A property with an `init` accessor takes the place of the stored properties it initializes.
              initializedByInitAccessor.formUnion(propertiesInitialized(by: initAccessor))
            } else if accessors.contains(where: { !$0.isObserver }) {
              // Only `willSet` and `didSet` can be attached to a stored property, anything else makes it computed.
              continue
            }
          }
        }
        if isLet && binding.initializer != nil {
          // A `let` with an initial value can't be assigned again.
          continue
        }
        var type = binding.typeAnnotation?.type
        if type == nil && binding.initializer == nil {
          // `var a, b: Int` also declares `a` as `Int`.
          type = bindings[(index + 1)...].lazy.compactMap { $0.typeAnnotation?.type }.first
        }
        if let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier {
          properties.append(
            StoredProperty(
              identifier: identifier,
              type: type,
              defaultValue: binding.initializer?.value.trimmedDescription
            )
          )
        } else if let tuplePattern = binding.pattern.as(TuplePatternSyntax.self) {
          properties += storedProperties(in: tuplePattern, type: type)
        }
      }
    }
    return properties.filter { !initializedByInitAccessor.contains($0.name) }
  }

  /// `var (a, b): (Int, Int)` declares two stored properties. They don't get a default value since the initial value
  /// can't be split up between them.
  private static func storedProperties(in pattern: TuplePatternSyntax, type: TypeSyntax?) -> [StoredProperty] {
    let elementTypes: [TypeSyntax]?
    if let tupleType = type?.as(TupleTypeSyntax.self), tupleType.elements.count == pattern.elements.count {
      elementTypes = tupleType.elements.map(\.type)
    } else {
      elementTypes = nil
    }
    var properties: [StoredProperty] = []
    for (index, element) in pattern.elements.enumerated() {
      let elementType = elementTypes?[index]
      if let identifier = element.pattern.as(IdentifierPatternSyntax.self)?.identifier {
        properties.append(StoredProperty(identifier: identifier, type: elementType, defaultValue: nil))
      } else if let nestedPattern = element.pattern.as(TuplePatternSyntax.self) {
        properties += storedProperties(in: nestedPattern, type: elementType)
      }
    }
    return properties
  }

  /// The properties listed in the `@storageRestrictions(initializes:)` attribute of `initAccessor`.
  private static func propertiesInitialized(by initAccessor: AccessorDeclSyntax) -> [String] {
    var result: [String] = []
    for case .attribute(let attribute) in initAccessor.attributes {
      guard attribute.attributeName.trimmedDescription == "storageRestrictions",
        case .argumentList(let arguments) = attribute.arguments
      else {
        continue
      }
      // Only the first element carries the `initializes:` label.
      var isInitializesList = false
      for argument in arguments {
        if let label = argument.label {
          isInitializesList = label.text == "initializes"
        }
        if isInitializesList {
          result.append(argument.expression.trimmedDescription)
        }
      }
    }
    return result
  }

  private static func indentation(of decl: some DeclGroupSyntax) -> (member: String, body: String) {
    let declIndentation = decl.firstToken(viewMode: .sourceAccurate)?.indentation.description ?? ""
    let inferredStep = (BasicFormat.inferIndentation(of: decl.root) ?? .spaces(4)).description
    guard let firstMemberToken = decl.memberBlock.members.firstToken(viewMode: .sourceAccurate),
      let memberIndentationTrivia = firstMemberToken.leadingTrivia.indentationAfterLastNewline
    else {
      let memberIndentation = declIndentation + inferredStep
      return (member: memberIndentation, body: memberIndentation + inferredStep)
    }
    let memberIndentation = memberIndentationTrivia.description
    // Use the step between the type and its members. `inferIndentation` isn't reliable for small files.
    let step: String
    if memberIndentation.count > declIndentation.count, memberIndentation.hasPrefix(declIndentation) {
      step = String(memberIndentation.dropFirst(declIndentation.count))
    } else {
      step = inferredStep
    }
    return (member: memberIndentation, body: memberIndentation + step)
  }

  private static func parameterType(for type: TypeSyntax) -> String {
    var result = ""
    if type.isFunctionType && !type.isEscaping {
      // The parameter gets stored in a property, so it has to be `@escaping`.
      result += "@escaping "
    }
    if let implicitlyUnwrappedOptional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      // Print `T!` as `T?`, like the compiler does for the implicit memberwise initializer.
      result += "\(implicitlyUnwrappedOptional.wrappedType.trimmedDescription)?"
    } else {
      result += type.trimmedDescription
    }
    return result
  }
}

// MARK: - Helper Extensions

extension Trivia {
  /// `nil` if the trivia doesn't contain a newline.
  fileprivate var indentationAfterLastNewline: Trivia? {
    guard let lastNewlineIndex = pieces.lastIndex(where: \.isNewline) else {
      return nil
    }
    let indentation = pieces[(lastNewlineIndex + 1)...].prefix { piece in
      switch piece {
      case .spaces, .tabs: return true
      default: return false
      }
    }
    return Trivia(pieces: indentation)
  }
}

extension TokenSyntax {
  /// Like `indentationOfLine`, but a comment in the previous token's trailing trivia doesn't confuse it.
  fileprivate var indentation: Trivia {
    return leadingTrivia.indentationAfterLastNewline ?? indentationOfLine
  }
}

extension AccessorDeclSyntax {
  fileprivate var isObserver: Bool {
    switch accessorSpecifier.tokenKind {
    case .keyword(.willSet), .keyword(.didSet):
      return true
    default:
      return false
    }
  }
}

extension TypeSyntax {
  fileprivate var isFunctionType: Bool {
    switch self.as(TypeSyntaxEnum.self) {
    case .functionType:
      return true
    case .attributedType(let attributedType):
      return attributedType.baseType.isFunctionType
    case .tupleType(let tupleType):
      guard let element = tupleType.elements.only, element.firstName == nil else {
        return false
      }
      return element.type.isFunctionType
    default:
      return false
    }
  }

  fileprivate var isEscaping: Bool {
    guard let attributedType = self.as(AttributedTypeSyntax.self) else {
      return false
    }
    return attributedType.attributes.contains { element in
      guard case .attribute(let attribute) = element else {
        return false
      }
      return attribute.attributeName.trimmedDescription == "escaping"
    }
  }

  fileprivate var isOptional: Bool {
    switch self.as(TypeSyntaxEnum.self) {
    case .optionalType, .implicitlyUnwrappedOptionalType:
      return true
    case .identifierType(let identifierType):
      return identifierType.name.text == "Optional" && identifierType.genericArgumentClause?.arguments.count == 1
    case .memberType(let memberType):
      return memberType.baseType.trimmedDescription == "Swift" && memberType.name.text == "Optional"
        && memberType.genericArgumentClause?.arguments.count == 1
    case .attributedType(let attributedType):
      return attributedType.baseType.isOptional
    default:
      return false
    }
  }
}
