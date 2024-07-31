# Modules

The SourceKit-LSP package contains the following non-testing modules.

### BuildServerProtocol

Swift types to represent the [Build Server Protocol (BSP) specification](https://build-server-protocol.github.io/docs/specification). These types should also be usable when implementing a BSP client and thus this module should not have any dependencies other than the LanguageServerProtocol module, with which it shares some types.

### BuildSystemIntegration

Defines the queries SourceKit-LSP can ask of a build system, like getting compiler arguments for a file, finding a target’s dependencies or preparing a target.

### CAtomics

Implementation of atomics for Swift using C. Once we can raise our deployment target to use the `Atomic` type from the Swift standard library, this module should be removed.

### CSKTestSupport

For testing, overrides `__cxa_atexit` to prevent registration of static destructors due to work around https://github.com/swiftlang/swift/issues/55112.


### Csourcekitd

Header file defining the interface to sourcekitd. This should stay in sync with [sourcekitd.h](https://github.com/swiftlang/swift/blob/main/tools/SourceKit/tools/sourcekitd/include/sourcekitd/sourcekitd.h) in the Swift repository.

### Diagnose

A collection of subcommands to the `sourcekit-lsp` executable that help SourceKit-LSP diagnose issues.

### InProcessClient

A simple type that allows launching a SourceKit-LSP server in-process, communicating in terms of structs from the `LanguageServerProtocol` module.

This should be the dedicated entry point for clients that want to run SourceKit-LSP in-process instead of launching a SourceKit-LSP server out-of-process and communicating with it using JSON RPC.

### LanguageServerProtocol

Swift types to represent the [Language Server Protocol (LSP) specification, version 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/). These types should also be usable when implementing an LSP client and thus this module should not have any dependencies.

### LanguageServerProtocolJSONRPC

A connection to or from a SourceKit-LSP server. Since message parsing can fail, it needs to handle errors in some way and the design decision here is to use SKLogging, which hardcodes `org.swift.sourcekit-lsp` as the default logging subsystem and thus makes the module unsuitable for generic clients.

### SemanticIndex

Contains the interface with which SourceKit-LSP queries the semantic index, adding up-to-date checks on top of the indexstore-db API. Also implements the types that manage background indexing.

### SKLogging

Types that are API-compatible with OSLog that allow logging to OSLog when building for Apple platforms and logging to stderr or files on non-Apple platforms. This should not be dependent on any LSP specific types and be portable to other packages.

### SKOptions

Configuration options to change how SourceKit-LSP behaves, based on [Configuration files](Configuration%20File.md).

### SKSupport

Contains SourceKit-LSP-specific helper functions. These fall into three different categories:
-  Extensions on top of `swift-tools-support-core`
- Functionality that can only be implemented by combining two lower-level modules that don't have a shared dependency, like `SKLogging` + `LanguageServerProtocol`
- Types that should be sharable by the different modules that implement SourceKit-LSP but that are not generic enough to fit into `SwiftExtensions`, like `ExperimentalFeatures`.

### SKTestSupport

A collection of utilities useful for writing tests for SourceKit-LSP and which are not specific to a single test module.

### sourcekit-lsp

This executable target that produces the `sourcekit-lsp` binary.

### SourceKitD

A Swift interface to talk to sourcekitd.

### SourceKitLSP

This is the core module that implements the SourceKit-LSP server.

### SwiftExtensions

Extensions to the Swift standard library and Foundation. Should not have any other dependencies. Any types in here should theoretically make senses to put in the Swift standard library or Foundation and they shouldn't be specific to SourceKit-LSP

#### ToolchainRegistry

Discovers Swift toolchains on the system.
