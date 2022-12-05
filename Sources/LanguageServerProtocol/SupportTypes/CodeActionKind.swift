//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A code action kind.
///
/// In LSP, this is a string, so we don't use a closed set.
public struct CodeActionKind: RawRepresentable, Codable, Hashable {

  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Empty kind.
  public static let empty: CodeActionKind = CodeActionKind(rawValue: "")

  /// QuickFix action, such as FixIt.
  public static let quickFix: CodeActionKind = CodeActionKind(rawValue: "quickfix")

  /// Base kind for refactoring action.
  public static let refactor: CodeActionKind = CodeActionKind(rawValue: "refactor")

  /// Base kind for refactoring extract action, such as extract method or extract variable.
  public static let refactorExtract: CodeActionKind = CodeActionKind(rawValue: "refactor.extract")

  /// Base kind for refactoring inline action, such as inline method, or inline variable.
  public static let refactorInline: CodeActionKind = CodeActionKind(rawValue: "refactor.inline")

  /// Refactoring rewrite action.
  // FIXME: what is this?
  public static let refactorRewrite: CodeActionKind = CodeActionKind(rawValue: "refactor.rewrite")

  /// Source action that applies to the entire file.
  // FIXME: what is this?
  public static let source: CodeActionKind = CodeActionKind(rawValue: "source")

  /// Organize imports action.
  public static let sourceOrganizeImports: CodeActionKind = CodeActionKind(rawValue: "source.organizeImports")

   /// Base kind for a 'fix all' source action: `source.fixAll`.
   ///
   /// 'Fix all' actions automatically fix errors that have a clear fix that
   /// do not require user input. They should not suppress errors or perform
   /// unsafe fixes such as generating new types or classes.
  public static let sourceFixAll: CodeActionKind = CodeActionKind(rawValue: "source.fixAll")
}
