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

import SwiftSyntax

package extension MemberAccessExprSyntax {
  /// The fully-qualified name of this instance (subject to available
  /// information.)
  ///
  /// The value of this property are all the components of the based name
  /// name joined together with `.`.
  var fullyQualifiedName: String {
    components.joined(separator: ".")
  }

  /// The name components of this instance (subject to available
  /// information.)
  ///
  /// The value of this property is this base name of this instance,
  /// i.e. the string value of `base` preceeded with any preceding base names
  /// and followed by its `name` property.
  ///
  /// For example, if this instance represents
  /// the expression `x.y.z(123)`, the value of this property is
  /// `["x", "y", "z"]`.
  var components: [String] {
    if let declReferenceExpr = base?.as(DeclReferenceExprSyntax.self) {
      return [declReferenceExpr.baseName.text, declName.baseName.text]
    } else if let baseMemberAccessExpr = base?.as(MemberAccessExprSyntax.self) {
      return baseMemberAccessExpr.components + [declName.baseName.text]
    }
    return [declName.baseName.text]
  }
}

package extension ExprSyntax {
  var fullyQualifiedName: String? {
    if let declRef = self.as(DeclReferenceExprSyntax.self) {
      return declRef.baseName.text
    } else if let memberAccess = self.as(MemberAccessExprSyntax.self) {
      return memberAccess.fullyQualifiedName
    }
    return nil
  }
}
