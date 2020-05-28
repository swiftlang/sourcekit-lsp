import sourcekitd
import LanguageServerProtocol
import IndexStoreDB

public struct SemanticToken {
    let name: String?
    let line: Int
    let startChar: Int
    let length: Int
    let tokenType: sourcekitd_uid_t.SemanticTokenKind?
    let tokenModifiers: Int
}

final class SemanticTokenParser {

  private let sourcekitd: SwiftSourceKitFramework
  private let snapshot: DocumentSnapshot
  private let indexedSymbolNames: [String]

  init(sourcekitd: SwiftSourceKitFramework, snapshot: DocumentSnapshot, symbolNames: [String]) {
    self.sourcekitd = sourcekitd
    self.indexedSymbolNames = symbolNames
    self.snapshot = snapshot
  }

  func parseTokens(_ response: SKResponseDictionary) -> [SemanticToken] {
        let keys = sourcekitd.keys
        guard
          let offset: Int = response[keys.nameoffset] ?? response[keys.offset],
          let start: Position = snapshot.positionOf(utf8Offset: offset),
          let length: Int = response[keys.namelength] ?? response[keys.length],
          let kind: sourcekitd_uid_t = response[keys.kind]
        else { 
          return []
        }
        let name = response[keys.name] as String?
        let tokenType = getTokenType(kind: kind, name: name)
        let validName = getValidTokenName(name: name, kind: tokenType)
        let token = SemanticToken(
          name: name,
          line: start.line,
          startChar: start.utf16index,
          length: validName?.count ?? length,
          tokenType: tokenType,
          tokenModifiers: 0
        )
        var children: [SemanticToken]
        if let substructure: SKResponseArray = response[keys.substructure] {
          children = parseTokens(substructure)
        } else {
          children = []
        }
        return [token] + children
  }

  func parseTokens(_ response: SKResponseArray) -> [SemanticToken] {
    var result: [SemanticToken] = []
    response.forEach { (i: Int, value: SKResponseDictionary) in
      let token = parseTokens(value) 
      result.append(contentsOf: token)
      return true
    }
    return result
  }

  // FIXME: Basic editor.open sourkitd query is missing a lot of symbol data, marking unknown symbols as expr_call
  // to determine if expression is a type reference, it have to check if name of expression is included in indexed symbol list
  // this seems to be quite suboptimal
  private func getTokenType(kind: sourcekitd_uid_t, name: String?) -> sourcekitd_uid_t.SemanticTokenKind? {
    let values = sourcekitd.values
    if kind == values.expr_call, let name = name, indexedSymbolNames.contains(name) {
        return values.syntaxtype_type_identifier.asSemanticToken(values)
    }
    return kind.asSemanticToken(values)
  }
  
  private func getValidTokenName(name: String?, kind: sourcekitd_uid_t.SemanticTokenKind?) -> String? {
    guard let name = name, let kind = kind else { return nil }
    switch kind {
      case .function:
      // functions/method names are returned as f.e. 'foo(a:b:)' since we care about only function name, we have to adjust it
      // a little bit
        return String(name.split(separator: "(").first ?? "")
      default: 
        return name
    }
  }
}

