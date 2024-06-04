# Testing

Most tests in SourceKit-LSP are integration tests that create a `SourceKitLSPServer` instance in-process, initialize it and send messages to it. The test support modules essentially define four ways of creating test projects.

### `TestSourceKitLSPClient`

Launches a `SourceKitLSPServer` in-process. Documents can be opened within it but these documents don't have any representation on the file system. `TestSourceKitLSPClient` has the lowest overhead and is the basis for all the other test projects. Because there are no files on disk, this type cannot test anything that requires cross-file functionality or exercise requests that require an index.

### `IndexedSingleSwiftFileTestProject`

Creates a single `.swift` file on disk, indexes it and then opens it using a `TestSourceKitLSPClient`. This is the best choice for tests that require an index but don’t need to exercise any cross-file functionality.

### `SwiftPMTestProject`

Creates a SwiftPM project on disk that allows testing of cross-file and cross-module functionality. By default the `SwiftPMTestProject` does not build an index or build any Swift modules, which is often sufficient when testing cross-file functionality within a single module. When cross-module functionality or an index is needed, background indexing can be enabled using `enableBackgroundIndexing: true`, which waits for background indexing to finish before allowing any requests.

## `MultiFileTestProject`

This is the most flexible test type that writes arbitrary files to disk. It provides less functionality out-of-the-box but is capable of eg. representing workspaces with multiple SwiftPM projects or projects that have `compile_commands.json`.
