import LanguageServerProtocol
import SwiftSyntax

@resultBuilder
struct WorkspaceEditBuilder {
  static func buildBlock(_ components: BuildableWorkspaceEdit...) -> [BuildableWorkspaceEdit] {
    return components
  }
}

public protocol BuildableWorkspaceEdit {
  func asEdit(in scope: CodeActionScope) -> TextEdit
}

public struct Replace<OldTree: SyntaxProtocol, NewTree: SyntaxProtocol>: BuildableWorkspaceEdit {
  public var old: OldTree
  public var new: NewTree

  public init(_ old: OldTree, with new: NewTree) {
    self.old = old
    self.new = new
  }

  public func asEdit(in scope: CodeActionScope) -> TextEdit {
    let oldRange = self.old.totalByteRange
    let lower = scope.snapshot.positionOf(utf8Offset: self.old.positionAfterSkippingLeadingTrivia.utf8Offset) ?? Position(line: 0, utf16index: 0)
    let upper = scope.snapshot.positionOf(utf8Offset: oldRange.endOffset) ?? Position(line: 0, utf16index: 0)
    return TextEdit(range: Range(uncheckedBounds: (lower: lower, upper: upper)), newText: "\(self.new)")
  }
}

public struct Remove<Tree: SyntaxProtocol>: BuildableWorkspaceEdit {
  public var tree: Tree

  public init(_ tree: Tree) {
    self.tree = tree
  }

  public func asEdit(in scope: CodeActionScope) -> TextEdit {
    let oldRange = self.tree.totalByteRange
    let lower = scope.snapshot.positionOf(utf8Offset: self.tree.positionAfterSkippingLeadingTrivia.utf8Offset) ?? Position(line: 0, utf16index: 0)
    let upper = scope.snapshot.positionOf(utf8Offset: oldRange.endOffset) ?? Position(line: 0, utf16index: 0)
    return TextEdit(range: Range(uncheckedBounds: (lower: lower, upper: upper)), newText: "")
  }
}

public struct ProvidedAction {
  public var title: String
  public var edits: [BuildableWorkspaceEdit]

  public init(title: String, edits: [BuildableWorkspaceEdit]) {
    self.title = title
    self.edits = edits
  }

  public init(title: String, @WorkspaceEditBuilder edit: () -> [BuildableWorkspaceEdit]) {
    self.title = title
    self.edits = edit()
  }
}
