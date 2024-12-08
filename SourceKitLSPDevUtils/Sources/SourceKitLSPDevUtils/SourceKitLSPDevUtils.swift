import ArgumentParser

@main
struct SourceKitLSPDevUtils: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sourcekit-lsp-dev-utils",
        abstract: "Utilities for developing SourceKit-LSP",
        subcommands: [
            GenerateConfigSchema.self,
        ]
    )
}
