//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SourceKitD
import LanguageServerProtocol
import LSPLogging

/// Parses tokens from sourcekitd response dictionaries.
struct SyntaxHighlightingTokenParser {
  private let sourcekitd: SourceKitD

  init(sourcekitd: SourceKitD) {
    self.sourcekitd = sourcekitd
  }

  func parseTokens(_ response: SKDResponseDictionary, in snapshot: DocumentSnapshot, into tokens: inout [SyntaxHighlightingToken]) {
    let keys = sourcekitd.keys

    if let offset: Int = response[keys.offset],
       var length: Int = response[keys.length],
       let start: Position = snapshot.positionOf(utf8Offset: offset),
       let skKind: sourcekitd_uid_t = response[keys.kind],
       case (let kind, var modifiers)? = parseKindAndModifiers(skKind) {

      // If the name is escaped in backticks, we need to add two characters to the
      // length for the backticks.
      if modifiers.contains(.declaration),
         let index = snapshot.indexOf(utf8Offset: offset), snapshot.text[index] == "`" {
        length += 2
      }

      if let isSystem: Bool = response[keys.is_system], isSystem {
        modifiers.insert(.defaultLibrary)
      }

      if let end: Position = snapshot.positionOf(utf8Offset: offset + length) {
        let multiLineRange = start..<end
        let ranges = multiLineRange.splitToSingleLineRanges(in: snapshot)

        tokens += ranges.map {
          SyntaxHighlightingToken(
            range: $0,
            kind: kind,
            modifiers: modifiers
          )
        }
      }
    }

    if let substructure: SKDResponseArray = response[keys.substructure] {
      parseTokens(substructure, in: snapshot, into: &tokens)
    }
  }

  func parseTokens(_ response: SKDResponseArray, in snapshot: DocumentSnapshot, into tokens: inout [SyntaxHighlightingToken]) {
    response.forEach { (_, value) in
      parseTokens(value, in: snapshot, into: &tokens)
      return true
    }
  }

  private func parseKindAndModifiers(_ uid: sourcekitd_uid_t) -> (SyntaxHighlightingToken.Kind, SyntaxHighlightingToken.Modifiers)? {
    let api = sourcekitd.api
    let values = sourcekitd.values
    switch uid {
    case values.kind_keyword,
         values.syntaxtype_keyword:
      return (.keyword, [])
    case values.syntaxtype_attribute_builtin:
      return (.modifier, [])
    case values.decl_module:
      return (.namespace, [])
    case values.decl_class:
      return (.class, [.declaration])
    case values.ref_class:
      return (.class, [])
    case values.decl_struct:
      return (.struct, [.declaration])
    case values.ref_struct:
      return (.struct, [])
    case values.decl_enum:
      return (.enum, [.declaration])
    case values.ref_enum:
      return (.enum, [])
    case values.decl_enumelement:
      return (.enumMember, [.declaration])
    case values.ref_enumelement:
      return (.enumMember, [])
    case values.decl_protocol:
      return (.interface, [.declaration])
    case values.ref_protocol:
      return (.interface, [])
    case values.decl_associatedtype,
         values.decl_typealias,
         values.decl_generic_type_param:
      return (.typeParameter, [.declaration])
    case values.ref_associatedtype,
         values.ref_typealias,
         values.ref_generic_type_param:
      return (.typeParameter, [])
    case values.decl_function_free:
      return (.function, [.declaration])
    case values.decl_function_method_static,
         values.decl_function_method_class,
         values.decl_function_constructor:
      return (.method, [.declaration, .static])
    case values.decl_function_method_instance,
         values.decl_function_destructor,
         values.decl_function_subscript:
      return (.method, [.declaration])
    case values.ref_function_free:
      return (.function, [])
    case values.ref_function_method_static,
         values.ref_function_method_class,
         values.ref_function_constructor:
      return (.method, [.static])
    case values.ref_function_method_instance,
         values.ref_function_destructor,
         values.ref_function_subscript:
      return (.method, [])
    case values.decl_function_operator_prefix,
         values.decl_function_operator_postfix,
         values.decl_function_operator_infix:
      return (.operator, [.declaration])
    case values.ref_function_operator_prefix,
         values.ref_function_operator_postfix,
         values.ref_function_operator_infix:
      return (.operator, [])
    case values.decl_var_static,
         values.decl_var_class,
         values.decl_var_instance:
      return (.property, [.declaration])
    case values.decl_var_parameter:
      // SourceKit seems to use these to refer to parameter labels,
      // therefore we don't use .parameter here (which LSP clients like
      // VSCode seem to interpret as variable identifiers, however
      // causing a 'wrong highlighting' e.g. of `x` in `f(x y: Int) {}`)
      return (.function, [.declaration])
    case values.ref_var_static,
         values.ref_var_class,
         values.ref_var_instance:
      return (.property, [])
    case values.decl_var_local,
         values.decl_var_global:
      return (.variable, [.declaration])
    case values.ref_var_local,
         values.ref_var_global:
      return (.variable, [])
    case values.syntaxtype_comment,
         values.syntaxtype_comment_marker,
         values.syntaxtype_comment_url:
      return (.comment, [])
    case values.syntaxtype_doccomment,
         values.syntaxtype_doccomment_field:
      return (.comment, [.documentation])
    case values.syntaxtype_type_identifier:
      return (.type, [])
    case values.syntaxtype_number:
      return (.number, [])
    case values.syntaxtype_string:
      return (.string, [])
    case values.syntaxtype_identifier:
      return (.identifier, [])
    default:
      let ignoredKinds: Set<sourcekitd_uid_t> = [
        values.syntaxtype_string_interpolation_anchor,
      ]
      if !ignoredKinds.contains(uid) {
        let name = api.uid_get_string_ptr(uid).map(String.init(cString:))
        log("Unknown token kind: \(name ?? "?")", level: .debug)
      }
      return nil
    }
  }
}

extension Range where Bound == Position {
  /// Splits a potentially multi-line range to multiple single-line ranges.
  fileprivate func splitToSingleLineRanges(in snapshot: DocumentSnapshot) -> [Self] {
    if isEmpty {
      return []
    }

    if lowerBound.line == upperBound.line {
      return [self]
    }

    guard let startIndex = snapshot.index(of: lowerBound),
          let endIndex = snapshot.index(of: upperBound) else {
      fatalError("Range \(self) reaches outside of the document")
    }

    let text = snapshot.text[startIndex..<endIndex]
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

    return lines
      .enumerated()
      .lazy
      .map { (i, content) in
        let start = Position(
          line: lowerBound.line + i,
          utf16index: i == 0 ? lowerBound.utf16index : 0
        )
        let end = Position(
          line: start.line,
          utf16index: start.utf16index + content.utf16.count
        )
        return start..<end
      }
      .filter { !$0.isEmpty }
  }

  /// **Public for testing**
  public func _splitToSingleLineRanges(in snapshot: DocumentSnapshot) -> [Self] {
    splitToSingleLineRanges(in: snapshot)
  }
}
