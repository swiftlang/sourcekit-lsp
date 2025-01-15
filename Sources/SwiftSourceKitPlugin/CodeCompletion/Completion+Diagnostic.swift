//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension CompletionItem {
  /// A diagnostic associated with a given completion, for example, because it
  /// is a completion for a deprecated declaration.
  struct Diagnostic {
    enum Severity {
      case note
      case remark
      case warning
      case error
    }

    var severity: Severity
    var description: String

    init(severity: Severity, description: String) {
      self.severity = severity
      self.description = description
    }
  }
}
