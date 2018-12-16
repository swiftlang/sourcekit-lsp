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

public struct CodeActionRequest: TextDocumentRequest, Hashable {
    public static let method: String = "textDocument/codeAction"
    public typealias Response = [CodeAction]?

    public var textDocument: TextDocumentIdentifier

    /// The range at which this code action should be applied.
    public var range: PositionRange

    public var context: CodeActionContext
}

public struct CodeActionContext: Codable, Hashable {

    public var diagnostics: [Diagnostic]
}

public struct CodeAction: Codable, Hashable, ResponseType {
  public var title: String

  public var kind: CodeActionKind

  public var edit: WorkspaceEdit

  public init(title: String, kind: CodeActionKind = CodeActionKind.quickFix, edit: WorkspaceEdit) {
    self.title = title
    self.kind = kind
    self.edit = edit
  }
}
