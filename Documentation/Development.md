# Development

This document contains notes about development and testing of SourceKit-LSP.

## Table of Contents

* [Debugging](#debugging)
* [Writing Tests](#writing-tests)

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

SourceKit test projects should be put in the `Tests/INPUTS` directory. Generally, they should use the [Tibs](#tibs) build system to define their sources and targets. An exception is for tests that need to specifically test the interaction with the Swift Package Manager. An example Tibs test project might look like:

```
Tests/
  Inputs/
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

## Tibs

We use Tibs, the "Test Index Build System" from the IndexStoreDB project to provide build system support for test projects, including getting compiler arguments and building an index. 
For much more information about Tibs, see [IndexStoreDB/Documentation/Tibs.md](https://github.com/apple/indexstore-db/blob/master/Documentation/Tibs.md).
