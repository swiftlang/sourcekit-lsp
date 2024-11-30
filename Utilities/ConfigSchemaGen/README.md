# Configuration Schema Generation for SourceKit-LSP

This directory contains a tool to generate a JSON schema and Markdown
documentation for the SourceKit-LSP configuration file format
(`.sourcekit-lsp/config.json`) from the Swift type definitions in `SKOptions`
Swift module.

To regenerate the schema and documentation, run the following command from the
root of the repository:

```sh
swift run --package-path Utilities/ConfigSchemaGen
```

