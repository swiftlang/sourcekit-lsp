# Modules

The SourceKit-LSP package contains the following non-testing modules.

### BuildServerIntegration

Defines the queries SourceKit-LSP can ask of a build server, like getting compiler arguments for a file, finding a target’s dependencies or preparing a target.

### CCompletionScoring

A small C library containing helpers used in completion scoring.

### CSKTestSupport

For testing, overrides `__cxa_atexit` to prevent registration of static destructors as a workaround for https://github.com/swiftlang/swift/issues/55112.

### ClangLanguageService

Implements the C/C++ language service by managing a `clangd` process, forwarding LSP messages, and integrating build settings from SourceKit-LSP workspaces.

### CompletionScoring

Implements SourceKit-LSP’s code completion ranking logic, combining text matching and semantic signals to prioritize completion results.

### CompletionScoringTestSupport

Shared fixtures and helper utilities used by completion scoring tests, including deterministic random generation and symbol data setup.

### Csourcekitd

Header file defining the interface to sourcekitd. This should stay in sync with [sourcekitd.h](https://github.com/swiftlang/swift/blob/main/tools/SourceKit/tools/sourcekitd/include/sourcekitd/sourcekitd.h) in the Swift repository.

### Diagnose

A collection of subcommands to the `sourcekit-lsp` executable that help SourceKit-LSP diagnose issues.

### DocumentationLanguageService

Implements documentation-focused language features (DocC-based requests).

### InProcessClient

An in-process client API for launching a SourceKit-LSP server in the same process and communicating with typed requests/responses from [`LanguageServerProtocol`](https://github.com/swiftlang/swift-tools-protocols/tree/main/Sources/LanguageServerProtocol).

This should be the dedicated entry point for clients that want to run SourceKit-LSP in-process instead of launching a SourceKit-LSP server out-of-process and communicating with it using JSON RPC.

### LanguageServerProtocolExtensions

SourceKit-LSP-specific extensions on top of [`LanguageServerProtocol`](https://github.com/swiftlang/swift-tools-protocols/tree/main/Sources/LanguageServerProtocol).

### SKOptions

Configuration options to change how SourceKit-LSP behaves, based on [Configuration files](../Documentation/Configuration%20File.md).

### SKTestSupport

A collection of utilities useful for writing tests for SourceKit-LSP and which are not specific to a single test module.

### SKUtilities

Types that should be shared by the different modules that implement SourceKit-LSP but that are not generic enough to fit into `SwiftExtensions` or that need to depend on `SKLogging` and thus can’t live in `SwiftExtensions`.

### SemanticIndex

Contains the interface with which SourceKit-LSP queries the semantic index, adding up-to-date checks on top of the indexstore-db API. Also implements the types that manage background indexing.

### sourcekit-lsp

The executable target that produces the `sourcekit-lsp` binary.

### SourceKitD

A Swift interface to talk to sourcekitd.

### SourceKitLSP

This is the core module that implements the SourceKit-LSP server.

### SwiftExtensions

Extensions to the Swift standard library and Foundation. Should not have any other dependencies. Any types in here should theoretically make sense to put in the Swift standard library or Foundation and they shouldn't be specific to SourceKit-LSP

### SwiftLanguageService

Implements the Swift language service which contains the main logic for handling Swift-specific LSP requests, including code completion, diagnostics, and symbol information.

### SwiftSourceKitClientPlugin

Client-side sourcekitd plugin entry point that initializes SourceKit-LSP plugin support.

### SwiftSourceKitPlugin

Main sourcekitd service plugin that intercepts and handles completion-related requests, providing SourceKit-LSP’s custom completion pipeline inside sourcekitd.

### SwiftSourceKitPluginCommon

Shared plugin infrastructure used by `SwiftSourceKitPlugin` and `SwiftSourceKitClientPlugin`.

### TSCExtensions

Extensions on top of `swift-tools-support-core` that might integrate with modules from sourcekit-lsp.

### ToolchainRegistry

Discovers Swift toolchains on the system.
