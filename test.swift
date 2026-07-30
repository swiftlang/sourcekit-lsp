import SwiftSyntax
import SwiftParser

let source = """
func testFoo() throws {
  throw XCTSkip("Disabled")
  print("Hello")
}
"""

let tree = Parser.parse(source: source)
let function = tree.statements.first!.item.as(FunctionDeclSyntax.self)!
let body = function.body!
let firstStatement = body.statements.first!
let start = firstStatement.position
let end = firstStatement.endPosition

print("--- Original ---")
print(source)
print("--- Removed ---")
let startIdx = source.utf8.index(source.utf8.startIndex, offsetBy: start.utf8Offset)
let endIdx = source.utf8.index(source.utf8.startIndex, offsetBy: end.utf8Offset)
var modified = source
modified.replaceSubrange(startIdx..<endIdx, with: "")
print(modified)

let secondStatement = body.statements.dropFirst().first!
print("--- Trivia ---")
print("First stmt leading: \(firstStatement.leadingTrivia.debugDescription)")
print("First stmt trailing: \(firstStatement.trailingTrivia.debugDescription)")
print("Second stmt leading: \(secondStatement.leadingTrivia.debugDescription)")
print("Second stmt trailing: \(secondStatement.trailingTrivia.debugDescription)")
