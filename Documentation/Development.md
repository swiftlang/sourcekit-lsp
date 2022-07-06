# Development

This document contains notes about development and testing of SourceKit-LSP.

## Table of Contents

* [Getting Started Developing SourceKit-LSP](#getting-started-developing-sourcekit-lsp)
* [Building SourceKit-LSP](#building-sourcekit-lsp)
* [Toolchains](#toolchains)
* [Debugging](#debugging)
* [Writing Tests](#writing-tests)

## Getting Started Developing SourceKit-LSP

For maximum compatibility with toolchain components such as the Swift Package Manager, the only supported way to develop SourceKit-LSP is with the latest toolchain snapshot. We make an effort to keep the build and tests working with the latest release of Swift, but this is not always possible.

1. Install the latest "Trunk Development (main)" toolchain snapshot from https://swift.org/download/#snapshots. **If you're looking for swift-5.x**, use the `swift-5.x-branch` of SourceKit-LSP with the latest swift-5.x toolchain snapshot. See [Toolchains](#toolchains) for more information.

2. Build the language server executable `sourcekit-lsp` using `swift build`. See [Building](#building-sourcekit-lsp) for more information.

3. Configure your editor to use the newly built `sourcekit-lsp` executable and the toolchain snapshot. See [Editors](../Editors) for more information about editor integration.

4. Build the project you are editing with `swift build` using the toolchain snapshot. The language server depends on the build to provide module dependencies and to update the global index.

## Building SourceKit-LSP

Install the latest snapshot from https://swift.org/download/#snapshots. SourceKit-LSP builds with the latest toolchain snapshot of the corresponding branch (e.g. to build the *main* branch, use the latest *main* snapshot of the toolchain). See [Toolchains](#toolchains) for more information about supported toolchains.

SourceKit-LSP is built using the [Swift Package Manager](https://github.com/apple/swift-package-manager). For a standard debug build on the command line:

### macOS

```sh
$ export TOOLCHAINS=swift
$ swift package update
$ swift build
```

### Linux

Install the following dependencies of SourceKit-LSP:

* libsqlite3-dev libncurses5-dev python3 ninja-build

```sh
$ export PATH="<path_to_swift_toolchain>/usr/bin:${PATH}"
$ swift package update
$ swift build -Xcxx -I<path_to_swift_toolchain>/usr/lib/swift -Xcxx -I<path_to_swift_toolchain>/usr/lib/swift/Block
```

Setting `PATH` as described above is important even if `<path_to_swift_toolchain>/usr/bin` is already in your `PATH` because `/usr/bin` must be the **first** path to search.

After building, the server will be located at `.build/debug/sourcekit-lsp`, or a similar path, if you passed any custom options to `swift build`. Editors will generally need to be provided with this path in order to run the newly built server - see [Editors](../Editors) for more information about configuration.

SourceKit-LSP is designed to build against the latest SwiftPM, so if you run into any issue make sure you have the most up-to-date dependencies by running `swift package update`.

### Windows

The user must provide the following dependencies for SourceKit-LSP:
- SQLite3
- ninja

```cmd
> swift build -Xcc -I<absolute path to SQLite header search path> -Xlinker -L<absolute path to SQLite library search path> -Xcc -I%SDKROOT%\usr\include -Xcc -I%SDKROOT%\usr\include\Block
```

The header and library search paths must be passed to the build by absolute
path.  This allows the clang importer and linker to find the dependencies.

Additionally, as SourceKit-LSP depends on libdispatch and the Blocks runtime,
which are part of the SDK, but not in the default search path, need to be
explicitly added.

### Docker

SourceKit-LSP should run out of the box using the [Swift official Docker images](https://swift.org/download/#docker). To build `sourcekit-lsp` from source and run its test suite, follow the steps in the *Linux* section. In the official docker images, the toolchain is located at `/`.

If you are seeing slow compile times, you will most likely need to increase the memory available to the Docker container.

## Toolchains

SourceKit-LSP depends on tools such as `sourcekitd` and `clangd`, which it loads at runtime from an installed toolchain.

### Recommended Toolchain

Use the latest toolchain snapshot from https://swift.org/download/#snapshots. SourceKit-LSP is designed to be used with the latest toolchain snapshot of the corresponding branch.

| SourceKit-LSP branch | Toolchain |
|:---------------------|:----------|
| main                 | Trunk Development (main) |
| swift-5.2-branch     | Swift 5.2 Development |
| swift-5.1-branch     | Swift 5.1.1+ |

*Note*: there is no branch of SourceKit-LSP that supports Swift 5.0.

### Selecting the Toolchain

After installing the toolchain, SourceKit-LSP needs to know the path to the toolchain.

* On macOS, the toolchain is installed in `/Library/Developer/Toolchains/` with an `.xctoolchain` extension. The most recently installed toolchain is symlinked as `/Library/Developer/Toolchains/swift-latest.xctoolchain`.  If you opted to install for the current user only in the installer, the same paths will be under the home directory, e.g. `~/Library/Developer/Toolchains/`.

* On Linux, the toolchain is wherever the snapshot's `.tar.gz` file was extracted.

Your editor may have a way to configure the toolchain path directly via a configuration setting, or it may allow you to override the process environment variables used when launching `sourcekit-lsp`. See [Editors](../Editors) for more information.

Otherwise, the simplest way to configure the toolchain is to set the following environment variable to the absolute path of the toolchain.

```sh
SOURCEKIT_TOOLCHAIN_PATH=<toolchain>
```

## Debugging

You can attach LLDB to SourceKit-LSP and set breakpoints to debug. You may want to instruct LLDB to wait for the sourcekit-lsp process to launch and then start your editor, which will typically launch
SourceKit-LSP as soon as you open a Swift file:

```sh
$ lldb -w -n sourcekit-lsp
```

If you are using the Xcode project, go to Debug, Attach to Process by PID or Name.

### Print SourceKit Logs

You can configure SourceKit-LSP to print log information from SourceKit to stderr by setting the following environment variable:

```sh
SOURCEKIT_LOGGING="N"
```

Where "N" configures the log verbosity and is one of the following numbers: 0 (error), 1 (warning), 2 (info), or 3 (debug).

## Writing Tests

As much as is practical, all code should be covered by tests. New tests can be added under the `Tests` directory and should use `XCTest`. The rest of this section will describe the additional tools available in the `SKTestSupport` module to make it easier to write good and efficient tests.

### Test Projects (Fixtures)

SourceKit test projects should be put in the `SKTestSupport/INPUTS` directory. Generally, they should use the [Tibs](#tibs) build system to define their sources and targets. An exception is for tests that need to specifically test the interaction with the Swift Package Manager. An example Tibs test project might look like:

```
SKTestSupport/
  INPUTS/
    MyTestProj/
      a.swift
      b.swift
      c.cpp
```

Where `project.json` describes the project's targets, for example

```
{ "sources": ["a.swift", "b.swift", "c.cpp"] }
```

Tibs supports more advanced project configurations, such as multiple swift modules with dependencies, etc. For much more information about Tibs, including what features it supports and how it works, see [Tibs](#tibs).

### SKTibsTestWorkspace

The `SKTibsTestWorkspace` pulls together the various pieces needed for working with tests, including opening a connection to the language server, building the project to produce index data, loading source code into open documents, etc.

To create a `SKTibsTestWorkspace`, use the `staticSourceKitTibsWorkspace` method (the intent is to provide a `mutableSourceKitTibsWorkspace` method in the future for tests that mutate source code).

```swift
func testFoo() {
  // Create the workspace, including opening a connection to the TestServer.
  guard let ws = try staticSourceKitTibsWorkspace(name: "MyTestProj") else { return }
  let loc = ws.testLoc("myLocation")

  // Build the project and populate the index.
  try ws.buildAndIndex()

  // Open a document from the test project sources.
  try ws.openDocument(loc.url, language: .swift)

  // Send requests to the server.
  let response = try ws.sk.sendSync(...)
}
```

#### Source Locations

It is common to want to refer to specific locations in the source code of a test project. This is supported using inline comment syntax.

```swift
Test.swift:
func /*myFuncDef*/myFunc() {
  /*myFuncCall*/myFunc()
}
```

In a test, these locations can be referenced by name. The named location is immediately after the comment.

```swift

let loc = ws.testLoc("myFuncDef")
// TestLocation(url: ..., line: 1, column: 19)
```

`TestLocation`s can be easily converted to LSP `Location` and `Position`s.

```swift
Location(ws.testLoc("aaa:call"))
Position(ws.testLoc("aaa:call"))
```

### Long tests

Tests that run longer than approx. 1 second are only executed if the the `SOURCEKIT_LSP_ENABLE_LONG_TESTS` environment variable is set to `YES` or `1`. This, in particular, includes the crash recovery tests.

## Tibs

We use Tibs, the "Test Index Build System" from the IndexStoreDB project to provide build system support for test projects, including getting compiler arguments and building an index. 
For much more information about Tibs, see [IndexStoreDB/Documentation/Tibs.md](https://github.com/apple/indexstore-db/blob/main/Documentation/Tibs.md).
