import Foundation
import SymbolKit

/// Generates a JSON string that represents an empty symbol graph for the given module name.
package func emptySymbolGraph(forModule moduleName: String) throws -> String? {
  let symbolGraph = SymbolGraph(
    metadata: SymbolGraph.Metadata(
      formatVersion: SymbolGraph.SemanticVersion(major: 0, minor: 0, patch: 0),
      generator: "SourceKit-LSP"
    ),
    module: SymbolGraph.Module(name: moduleName, platform: SymbolGraph.Platform()),
    symbols: [],
    relationships: []
  )
  let data = try JSONEncoder().encode(symbolGraph)
  return String(data: data, encoding: .utf8)
}
