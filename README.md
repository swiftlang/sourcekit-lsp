# SourceKit-LSP

SourceKit-LSP is an implementation of the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) (LSP) for Swift and C-based languages. It provides features like code-completion and jump-to-definition to editors that support LSP. SourceKit-LSP is built on top of [sourcekitd](https://github.com/apple/swift/tree/master/tools/SourceKit) and [clangd](https://clang.llvm.org/extra/clangd.html) for high-fidelity language support, and provides a powerful source code index as well as cross-language support. SourceKit-LSP supports projects that use the Swift Package Manager.

## Getting Started

SourceKit-LSP is under heavy development! The best way to try it out is to install a recent Swift development toolchain from https://swift.org/download/#snapshots. Make sure you build your package with the same toolchain as you got sourcekit-lsp from to ensure compatibility.

### Using a Swift Toolchain from Swift.org

1. Install the latest master or 5.1 development toolchain snapshot from https://swift.org/download/#snapshots.

2. Configure your editor to use the `sourcekit-lsp` executable from the toolchain snapshot. See [Editors](Editors) for more information about editor integration.

3. Build the project you are working on with `swift build` using the same toolchain snapshot. The language server depends on the build to provide module dependencies and to update the global index.

## Development

For more information about developing SourceKit-LSP itself, see [Development](Documentation/Development.md).

## Indexing While Building

SourceKit-LSP uses a global index called [IndexStoreDB](https://github.com/apple/indexstore-db) to provide features that cross file or module boundaries, such as jump-to-definition or find-references. To efficiently create an index of your source code we use a technique called "indexing while building". When the project is compiled for debugging using `swift build`, the compiler (swiftc or clang) automatically produces additional raw index data that is read by our indexer. Producing this information during compilation saves work and ensures that any time the project is built the index is updated and fully accurate.

In the future we intend to also provide automatic background indexing so that we can update the index in between builds or to include code that's not always built like unit tests. In the meantime, building your project should bring our index up to date.

## Status

SourceKit-LSP is still in early development, so you may run into rough edges with any of the features. The following table shows the status of various features when using the latest development toolchain snapshot. See [Caveats](#caveats) for important known issues you may run into.

| Feature | Status | Notes |
|---------|:------:|-------|
| Swift | ✅ | |
| C/C++/ObjC | ✅ | Uses [clangd](https://clangd.github.io) |
| Code completion | ✅ | |
| Quick Help (Hover) | ✅ | |
| Diagnostics | ✅ | |
| Fix-its | ✅ | |
| Jump to Definition | ✅ | |
| Find References | ✅ | |
| Background Indexing | ❌ | Build project to update the index using [Indexing While Building](#indexing-while-building) |
| Workspace Symbols | ✅ | |
| Global Rename | ❌ | |
| Local Refactoring | ✅ | |
| Formatting | ❌ | |
| Folding | ✅ | |
| Syntax Highlighting | ❌ | Not currently part of LSP. |
| Document Symbols | ✅ |  |


### Caveats

* SwiftPM build settings are not updated automatically after files are added/removed.
	* **Workaround**: close and reopen the project after adding/removing files

* SourceKit-LSP does not update its global index in the background, but instead relies on indexing-while-building to provide data. This only affects global queries like find-references and jump-to-definition.
	* **Workaround**: build the project to update the index
