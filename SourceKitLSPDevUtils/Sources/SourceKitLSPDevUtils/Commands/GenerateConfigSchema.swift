import ArgumentParser
import ConfigSchemaGen

struct GenerateConfigSchema: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-config-schema",
        abstract: "Generate a JSON schema and documentation for the SourceKit-LSP configuration file"
    )

    func run() throws {
        try ConfigSchemaGen.generate()
    }
}
