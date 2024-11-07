# Implementing a BSP server

SourceKit-LSP can connect to any build system to provide semantic functionality through the [Build Server Protocol (BSP)](https://build-server-protocol.github.io). This is a short guide of the requests and notifications that a BSP server for SourceKit-LSP should implement. For more detailed information, refer to the [BSP spec](https://build-server-protocol.github.io/docs/specification) and the [SourceKit-LSP BSP Extensions](BSP%20Extensions.md). This document just references BSP methods and properties and those specification documents contain their documentation.

## Required lifecycle methods

In order to be launched and shut down successfully, the BSP server must implement the following methods

- `build/initialize`
- `build/initialized`
- `build/shutdown`
- `build/exit`

The `build/initialize` response must have `dataKind: "sourceKit"` and `data.sourceKitOptionsProvider: true`. In order to provide global code navigation features such as call hierarchy and global rename, the build server must set `data.indexDatabasePath` and `data.indexStorePath`.

## Retrieving build settings

In order to provide semantic functionality for source files, the BSP server must provide the following methods:

- `workspace/buildTargets`
- `buildTarget/sources`
- `textDocument/sourceKitOptions`
- `buildTarget/didChange`
- `workspace/waitForBuildSystemUpdates`

If the build system does not have a notion of targets, eg. because it provides build settings from a file akin to a JSON compilation database, it may use a single dummy target for all source files or a separate target for each source file, either choice will work.

If the build system loads the entire build graph during initialization, it may immediately return from `workspace/waitForBuildSystemUpdates`.

## Supporting background indexing

To support background indexing, the build system must set `data.prepareProvider: true` in the `build/initialize` response and implement the `buildTarget/prepare` method.

## Optional methods

The following methods are not necessary to implement for SourceKit-LSP to work but might help with the implementation of the build server.

- `build/logMessage`
- `build/taskStart`, `build/taskProgress`, and `build/taskFinish`
- `workspace/didChangeWatchedFiles`

## Build server discovery

To make your build server discoverable, create a [BSP connection specification](https://build-server-protocol.github.io/docs/overview/server-discovery) file named `buildServer.json` in the root of your project.
