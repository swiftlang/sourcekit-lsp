# SourceKit-LSP

SourceKit-LSP is an implementation of the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) (LSP) for Swift and C-based languages. It provides intelligent editor functionality like code-completion and jump-to-definition to editors that support LSP. SourceKit-LSP is built on top of [sourcekitd](https://github.com/apple/swift/tree/main/tools/SourceKit) and [clangd](https://clang.llvm.org/extra/clangd.html) for high-fidelity language support, and provides a powerful source code index as well as cross-language support. SourceKit-LSP supports projects that use the Swift Package Manager and projects that generate a `compile_commands.json` file, such as CMake.

## Getting Started

SourceKit-LSP is included in the the Swift toolchains available on [swift.org](http://swift.org/install/) and is bundled with [Xcode](http://developer.apple.com/xcode/).

[swift.org/tools](https://www.swift.org/tools) has a list of popular editors that support LSP and can thus be hooked up to SourceKit-LSP to provide intelligent editor functionality as well as set-up guides.

> [!IMPORTANT]
> SourceKit-LSP does not update its global index in the background or build Swift modules in the background. Thus, a lot of cross-module or global functionality is limited if the project hasn't been built recently. To update the index or rebuild the Swift modules, build your project or enable the experimental background indexing as described in [Enable Experimental Background Indexing](Documentation/Enable%20Experimental%20Background%20Indexing.md).

To learn more about SourceKit-LSP, refer to the [Documentation](Documentation).

> [!NOTE]
> If you are using SourceKit-LSP with a SwiftPM project in which you need to pass additional arguments to the `swift build` invocation, as is commonly the case for embedded projects, you need to teach SourceKit-LSP about those arguments as described in [Using SourceKit-LSP with Embedded Projects](Documentation/Using%20SourceKit-LSP%20with%20Embedded%20Projects.md).

## Reporting Issues

If you should hit any issues while using SourceKit-LSP, we appreciate bug reports on [GitHub Issue](https://github.com/swiftlang/sourcekit-lsp/issues/new/choose).

## Contributing

If you want to contribute code to SourceKit-LSP, see [CONTRIBUTING.md](CONTRIBUTING.md) for more information.
