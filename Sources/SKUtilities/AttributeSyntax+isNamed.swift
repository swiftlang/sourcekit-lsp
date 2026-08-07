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

package import SwiftSyntax

package extension AttributeSyntax {
  /// Check whether or not this attribute is named with the specified name and
  /// module.
  ///
  /// The attribute's name is accepted either without or with the specified
  /// module name as a prefix to allow for either syntax. The name of this
  /// attribute must not include generic type parameters.
  ///
  /// - Parameters:
  ///   - name: The `"."`-separated type name to compare against.
  ///   - moduleName: The module the specified type is declared in.
  ///
  /// - Returns: Whether or not this type has the given name.
  func isNamed(_ name: String, inModuleNamed moduleName: String) -> Bool {
    if let identifierType = attributeName.as(IdentifierTypeSyntax.self) {
      return identifierType.name.text == name
    } else if let memberType = attributeName.as(MemberTypeSyntax.self),
      let baseIdentifierType = memberType.baseType.as(IdentifierTypeSyntax.self),
      baseIdentifierType.genericArgumentClause == nil
    {
      return memberType.name.text == name && baseIdentifierType.name.text == moduleName
    }

    return false
  }
}
