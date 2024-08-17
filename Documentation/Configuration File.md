# Configuration File

`.sourcekit-lsp/config.json` configuration files can be used to modify the behavior of SourceKit-LSP in various ways. The following locations are checked. Settings in later configuration files override settings in earlier configuration files
- `~/.sourcekit-lsp/config.json`
- On macOS: `~/Library/Application Support/org.swift.sourcekit-lsp/config.json` from the various `Library` folders on the system
- If the `XDG_CONFIG_HOME` environment variable is set: `$XDG_CONFIG_HOME/sourcekit-lsp/config.json`
- Initialization options passed in the initialize request
- A `.sourcekit-lsp/config.json` file in a workspace’s root

The structure of the file is currently not guaranteed to be stable. Options may be removed or renamed.

## Structure

`config.json` is a JSON file with the following structure. All keys are optional and unknown keys are ignored.

- `swiftPM`: Dictionary with the following keys, defining options for SwiftPM workspaces
  - `configuration: "debug"|"release"`: The configuration to build the project for during background indexing and the configuration whose build folder should be used for Swift modules if background indexing is disabled. Equivalent to SwiftPM's `--configuration` option.
  - `scratchPath: string`: Build artifacts directory path. If nil, the build system may choose a default value. Equivalent to SwiftPM's `--scratch-path` option.
  - `swiftSDKsDirectory: string`: Equivalent to SwiftPM's `--swift-sdks-path` option
  - `swiftSDK: string`: Equivalent to SwiftPM's `--swift-sdk` option
  - `triple: string`: Equivalent to SwiftPM's `--triple` option
  - `cCompilerFlags: string[]`: Extra arguments passed to the compiler for C files. Equivalent to SwiftPM's `-Xcc` option.
  - `cxxCompilerFlags: string[]`: Extra arguments passed to the compiler for C++ files. Equivalent to SwiftPM's `-Xcxx` option.
  - `swiftCompilerFlags: string[]`: Extra arguments passed to the compiler for Swift files. Equivalent to SwiftPM's `-Xswiftc` option.
  - `linkerFlags: string[]`: Extra arguments passed to the linker. Equivalent to SwiftPM's `-Xlinker` option.
  - `disableSandbox: bool`: Disables running subprocesses from SwiftPM in a sandbox. Useful when running `sourcekit-lsp` in a sandbox because nested sandboxes are not supported.
- `compilationDatabase`: Dictionary with the following keys, defining options for workspaces with a compilation database
  - `searchPaths: string[]`: Additional paths to search for a compilation database, relative to a workspace root.
- `fallbackBuildSystem`: Dictionary with the following keys, defining options for files that aren't managed by any build system
  - `cCompilerFlags: string[]`: Extra arguments passed to the compiler for C files
  - `cxxCompilerFlags: string[]`: Extra arguments passed to the compiler for C++ files
  - `swiftCompilerFlags: string[]`: Extra arguments passed to the compiler for Swift files
- `clangdOptions: string[]`: Extra command line arguments passed to `clangd` when launching it
- `index`: Dictionary with the following keys, defining options related to indexing
    - `indexStorePath: string`: Directory in which a separate compilation stores the index store. By default, inferred from the build system.
    - `indexDatabasePath: string`: Directory in which the indexstore-db should be stored. By default, inferred from the build system.
    - `indexPrefixMap: [string: string]`: Path remappings for remapping index data for local use.
    - `maxCoresPercentageToUseForBackgroundIndexing: double`: A hint indicating how many cores background indexing should use at most (value between 0 and 1). Background indexing is not required to honor this setting
    - `updateIndexStoreTimeout: int`: Number of seconds to wait for an update index store task to finish before killing it.
- `logging`: Dictionary with the following keys, changing SourceKit-LSP’s logging behavior on non-Apple platforms. On Apple platforms, logging is done through the [system log](Diagnose%20Bundle.md#Enable%20Extended%20Logging). These options can only be set globally and not per workspace.
  - `logLevel: "debug"|"info"|"default"|"error"|"fault"`: The level from which one onwards log messages should be written.
  - `privacyLevel: "public"|"private"|"sensitive"`: Whether potentially sensitive information should be redacted. Default is `public`, which redacts potentially sensitive information.
- `defaultWorkspaceType: "buildserver"|"compdb"|"swiftpm"`: Overrides workspace type selection logic.
- `generatedFilesPath: string`: Directory in which generated interfaces and macro expansions should be stored.
- `backgroundIndexing: bool`: Explicitly enable or disable background indexing.
- `backgroundPreparationMode: "build"|"noLazy"|"enabled"`: Determines how background indexing should prepare a target. Possible values are: `build`: Build a target to prepare it, `noLazy`: Prepare a target without generating object files but do not do lazy type checking and function body skipping, `enabled`: Prepare a target without generating object files and the like
- `cancelTextDocumentRequestsOnEditAndClose: bool`: Whether sending a `textDocument/didChange` or `textDocument/didClose` notification for a document should cancel all pending requests for that document.
- `experimentalFeatures: string[]`: Experimental features to enable
- `swiftPublishDiagnosticsDebounce`: The time that `SwiftLanguageService` should wait after an edit before starting to compute diagnostics and sending a `PublishDiagnosticsNotification`.
