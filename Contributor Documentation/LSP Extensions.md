# LSP Extensions

SourceKit-LSP extends the LSP protocol in the following ways.

To enable some of these extensions, the client needs to communicate that it can support them. To do so, it should pass a dictionary for the `capabilities.experimental` field in the `initialize` request. For each capability to enable, it should pass an entry as follows.

```json
"<capabilityName>": {
  "supported": true
}
```

## `PublishDiagnosticsClientCapabilities`

Added field (this is an extension from clangd that SourceKit-LSP re-exposes):

```ts
/**
 * Requests that SourceKit-LSP send `Diagnostic.codeActions`.
 */
codeActionsInline?: bool
```

## `Diagnostic`

Added field (this is an extension from clangd that SourceKit-LSP re-exposes):

```ts
/**
 * All the code actions that address this diagnostic.
 */
codeActions: CodeAction[]?
```

## `DiagnosticRelatedInformation`

Added field (this is an extension from clangd that SourceKit-LSP re-exposes):

```ts
/**
 * All the code actions that address the parent diagnostic via this note.
 */
codeActions: CodeAction[]?
```

## Semantic token modifiers

Added the following cases from clangd

```ts
deduced = 'deduced'
virtual = 'virtual'
dependentName = 'dependentName'
usedAsMutableReference = 'usedAsMutableReference'
usedAsMutablePointer = 'usedAsMutablePointer'
constructorOrDestructor = 'constructorOrDestructor'
userDefined = 'userDefined'
functionScope = 'functionScope'
classScope = 'classScope'
fileScope = 'fileScope'
globalScope = 'globalScope'
```

## Semantic token types

Added the following cases from clangd

```ts
bracket = 'bracket'
label = 'label'
concept = 'concept'
unknown = 'unknown'
```

Added case

```ts
/**
 * An identifier that hasn't been further classified
 */
identifier = 'identifier'
```

## `textDocument/completion`

Added field:

```ts
/**
 * Options to control code completion behavior in Swift
 */
sourcekitlspOptions?: SKCompletionOptions;
```

with

```ts
interface SKCompletionOptions {
  /**
   * The maximum number of completion results to return, or `null` for unlimited.
   */
  maxResults?: int;
}
```

## `textDocument/doccDocumentation`

New request that generates documentation for a symbol at a given cursor location.

Primarily designed to support live preview of Swift documentation in editors.

This request looks up the nearest documentable symbol (if any) at a given cursor location within
a text document and returns a `DoccDocumentationResponse`. The response contains a string
representing single JSON encoded DocC RenderNode. This RenderNode can then be rendered in an
editor via https://github.com/swiftlang/swift-docc-render.

The position may be omitted for documentation within DocC markdown and tutorial files as they
represent a single documentation page. It is only required for generating documentation within
Swift files as they usually contain multiple documentable symbols.

Documentation can fail to be generated for a number of reasons. The most common of which being
that no documentable symbol could be found. In such cases the request will fail with a request
failed LSP error code (-32803) that contains a human-readable error message. This error message can
be displayed within the live preview editor to indicate that something has gone wrong.

At the moment this request is only available on macOS and Linux. SourceKit-LSP will advertise
`textDocument/doccDocumentation` in its experimental server capabilities if it supports it.

- params: `DoccDocumentationParams`
- result: `DoccDocumentationResponse`

```ts
export interface DoccDocumentationParams {
  /**
   * The document to generate documentation for.
   */
  textDocument: TextDocumentIdentifier;

  /**
   * The cursor position within the document. (optional)
   *
   * This parameter is only used in Swift files to determine which symbol to render.
   * The position is ignored for markdown and tutorial documents.
   */
  position?: Position;
}

export interface DoccDocumentationResponse {
  /**
   * The JSON encoded RenderNode that can be rendered by swift-docc-render.
   */
  renderNode: string;
}
```

## `textDocument/playgrounds`

New request for return the list of #Playground macro expansions in a given text document.

Primarily designed to allow editors to provide a list of available playgrounds in the project workspace and allow
jumping to the locations where the #Playground macro was expanded.

The request parses a given text document and returns the location, identifier, and optional label when available
for each #Playground macro expansion. The request is intended to be used in combination with the `workspace/playgrounds`
request where the `workspace/playgrounds` provides the full list of playgrounds in the workspace and `textDocument/playgrounds`
can be called after document changes. This way the editor can itself keep the list of playgrounds up to date without needing to
call `workspace/playgrounds` each time a document is changed.

SourceKit-LSP will advertise `textDocument/playgrounds` in its experimental server capabilities if it supports it.

- params: `DocumentPlaygroundParams`
- result: `PlaygroundItem[]`

```ts
export interface DocumentPlaygroundParams {
  /**
   * The document to parse for playgrounds.
   */
  textDocument: TextDocumentIdentifier;
}
/**
 * A `PlaygroundItem` represents an expansion of the #Playground macro, providing the editor with the
 * location of the playground and identifiers to allow executing the playground through a "swift play" command.
 */
export interface PlaygroundItem {
  /**
   * Unique identifier for the `PlaygroundItem`. Client can run the playground by executing `swift play <id>`.
   * 
   * This property is always present whether the `PlaygroundItem` has a `label` or not.
   *
   * Follows the format output by `swift play --list`.
   */
  id: string;

  /**
   * The label that can be used as a display name for the playground. This optional property is only available
   * for named playgrounds. For example: `#Playground("hello") { print("Hello!) }` would have a `label` of `"hello"`.
   */
  label?: string

  /**
   * The location of the of where the #Playground macro expansion occured in the source code.
   */
  location: Location
}
```

## `textDocument/symbolInfo`

New request for semantic information about the symbol at a given location.

This request looks up the symbol (if any) at a given text document location and returns
SymbolDetails for that location, including information such as the symbol's USR. The symbolInfo
request is not primarily designed for editors, but instead as an implementation detail of how
one LSP implementation (e.g. SourceKit) gets information from another (e.g. clangd) to use in
performing index queries or otherwise implementing the higher level requests such as definition.

This request is an extension of the `textDocument/symbolInfo` request defined by clangd.

- params: `SymbolInfoParams`
- result: `SymbolDetails[]`


```ts
export interface SymbolInfoParams {
  /**
   * The document in which to lookup the symbol location.
   */
  textDocument: TextDocumentIdentifier;

  /**
   * The document location at which to lookup symbol information.
   */
  position: Position;
}

interface ModuleInfo {
  /**
   * The name of the module in which the symbol is defined.
   */
  moduleName: string;

  /**
   * If the symbol is defined within a subgroup of a module, the name of the group. Otherwise `nil`.
   */
  groupName?: string;
}

interface SymbolDetails {
  /**
   * The name of the symbol, if any.
   */
  name?: string;

  /**
   * The name of the containing type for the symbol, if any.
   *
   * For example, in the following snippet, the `containerName` of `foo()` is `C`.
   *
   * ```c++
   * class C {
   *   void foo() {}
   * }
   */
  containerName?: string;

  /**
   * The USR of the symbol, if any.
   */
  usr?: string;

  /**
   * Best known declaration or definition location without global knowledge.
   *
   * For a local or private variable, this is generally the canonical definition location -
   * appropriate as a response to a `textDocument/definition` request. For global symbols this is
   * the best known location within a single compilation unit. For example, in C++ this might be
   * the declaration location from a header as opposed to the definition in some other
   * translation unit.
   */
  bestLocalDeclaration?: Location;

  /**
   * The kind of the symbol
   */
  kind?: SymbolKind;

  /**
   * Whether the symbol is a dynamic call for which it isn't known which method will be invoked at runtime. This is
   * the case for protocol methods and class functions.
   *
   * Optional because `clangd` does not return whether a symbol is dynamic.
   */
  isDynamic?: bool;

  /**
   * Whether this symbol is defined in the SDK or standard library.
   *
   * This property only applies to Swift symbols
   */
  isSystem?: bool;

  /**
   * If the symbol is dynamic, the USRs of the types that might be called.
   *
   * This is relevant in the following cases
   * ```swift
   * class A {
   *   func doThing() {}
   * }
   * class B: A {}
   * class C: B {
   *   override func doThing() {}
   * }
   * class D: A {
   *   override func doThing() {}
   * }
   * func test(value: B) {
   *   value.doThing()
   * }
   * ```
   *
   * The USR of the called function in `value.doThing` is `A.doThing` (or its
   * mangled form) but it can never call `D.doThing`. In this case, the
   * receiver USR would be `B`, indicating that only overrides of subtypes in
   * `B` may be called dynamically.
   */
  receiverUsrs?: string[];

  /**
   * If the symbol is defined in a module that doesn't have source information associated with it, the name and group
   * and group name that defines this symbol.
   *
   * This property only applies to Swift symbols.
   */
  systemModule?: ModuleInfo;
}
```

## `textDocument/tests`

New request that returns symbols for all the test classes and test methods within a file.

- params: `DocumentTestsParams`
- result: `TestItem[]`

```ts
interface TestTag {
  /**
   * ID of the test tag. `TestTag` instances with the same ID are considered to be identical.
   */
  id: string;
}

/**
 * A test item that can be shown an a client's test explorer or used to identify tests alongside a source file.
 *
 * A `TestItem` can represent either a test suite or a test itself, since they both have similar capabilities.
 *
 * This type matches the `TestItem` type in Visual Studio Code to a fair degree.
 */
interface TestItem {
  /**
   * Identifier for the `TestItem`.
   *
   * This identifier uniquely identifies the test case or test suite. It can be used to run an individual test (suite).
   */
  id: string;

  /**
   * Display name describing the test.
   */
  label: string;

  /**
   * Optional description that appears next to the label.
   */
  description?: string;

  /**
   * A string that should be used when comparing this item with other items.
   *
   * When `nil` the `label` is used.
   */
  sortText?: string;

  /**
   * Whether the test is disabled.
   */
  disabled: bool;

  /**
   * The type of test, eg. the testing framework that was used to declare the test.
   */
  style: string;

  /**
   * The location of the test item in the source code.
   */
  location: Location;

  /**
   * The children of this test item.
   *
   * For a test suite, this may contain the individual test cases or nested suites.
   */
  children: TestItem[];

  /**
   * Tags associated with this test item.
   */
  tags: TestTag[];
}

export interface DocumentTestsParams {
  /**
   * The text document.
  */
  textDocument: TextDocumentIdentifier;
}
```

## `sourceKit/_isIndexing`

Request from the client to the server querying whether SourceKit-LSP is currently performing an background indexing tasks, including target preparation.

> [!IMPORTANT]
> This request is experimental and may be modified or removed in future versions of SourceKit-LSP without notice. Do not rely on it.

- params: `IsIndexingParams`
- result: `IsIndexingResult`

```ts
export interface IsIndexingParams {}

export interface IsIndexingResult {
  /**
   * Whether SourceKit-LSP is currently performing an indexing task.
   */
  indexing: boolean;
}
```

## `window/didChangeActiveDocument`

New notification from the client to the server, telling SourceKit-LSP which document is the currently active primary document.

This notification should only be called for documents that the editor has opened in SourceKit-LSP using the `textDocument/didOpen` notification.

By default, SourceKit-LSP infers the currently active editor document from the last document that received a request.
If the client supports active reporting of the currently active document, it should check for the
`window/didChangeActiveDocument` experimental server capability. If that capability is present, it should respond with
the `window/didChangeActiveDocument` experimental client capability and send this notification whenever the currently
active document changes.

- params: `DidChangeActiveDocumentParams`

```ts
export interface DidChangeActiveDocumentParams {
  /**
   * The document that is being displayed in the active editor or `null` to indicate that either no document is active
   * or that the currently open document is not handled by SourceKit-LSP.
   */
  textDocument?: TextDocumentIdentifier;
}
```

## `window/logMessage`

Added fields:

```ts
/**
 * Asks the client to log the message to a log with this name, to organize log messages from different aspects (eg. general logging vs. logs from background indexing).
 *
 * Clients may ignore this parameter and add the message to the global log
 */
logName?: string;


/**
 * If specified, allows grouping log messages that belong to the same originating task together instead of logging
 * them in chronological order in which they were produced.
 *
 * LSP Extension guarded by the experimental `structured-logs` feature.
 */
structure?: StructuredLogBegin | StructuredLogReport | StructuredLogEnd;
```

With

```ts
/**
 * Indicates the beginning of a new task that may receive updates with `StructuredLogReport` or `StructuredLogEnd`
 * payloads.
 */
export interface StructuredLogBegin {
  kind: 'begin';

  /**
   * A succinct title that can be used to describe the task that started this structured.
   */
  title: string;

  /**
   * A unique identifier, identifying the task this structured log message belongs to.
   */
  taskID: string;
}


/**
 * Adds a new log message to a structured log without ending it.
 */
export interface StructuredLogReport {
  kind: 'report';
}

/**
 * Ends a structured log. No more `StructuredLogReport` updates should be sent for this task ID.
 *
 * The task ID may be re-used for new structured logs by beginning a new structured log for that task.
 */
export interface StructuredLogEnd {
  kind: 'end';
}
```

## `workspace/_setOptions`

New request to modify runtime options of SourceKit-LSP.

Any options not specified in this request will be left as-is.

> [!IMPORTANT]
> This request is experimental, guarded behind the `set-options-request` experimental feature, and may be modified or removed in future versions of SourceKit-LSP without notice. Do not rely on it.

- params: `SetOptionsParams`
- result: `void`

```ts
export interface SetOptionsParams {
  /**
   * `true` to pause background indexing or `false` to resume background indexing.
   */
  backgroundIndexingPaused?: bool;
}
```

## `workspace/_sourceKitOptions`

New request from the client to the server to retrieve the compiler arguments that SourceKit-LSP uses to process the document.

This request does not require the document to be opened in SourceKit-LSP. This is also why it has the `workspace/` instead of the `textDocument/` prefix.

> [!IMPORTANT]
> This request is experimental, guarded behind the `sourcekit-options-request` experimental feature, and may be modified or removed in future versions of SourceKit-LSP without notice. Do not rely on it.


- params: `SourceKitOptionsRequest`
- result: `SourceKitOptionsResult`

```ts
export interface SourceKitOptionsRequest {
  /**
   * The document to get options for
   */
  textDocument: TextDocumentIdentifier;

  /**
   * If specified, explicitly request the compiler arguments when interpreting the document in the context of the given
   * target.
   *
   * The target URI must match the URI that is used by the BSP server to identify the target. This option thus only
   * makes sense to specify if the client also controls the BSP server.
   *
   * When this is `null`, SourceKit-LSP returns the compiler arguments it uses when the the document is opened in the
   * client, ie. it infers a canonical target for the document.
   */
  target?: DocumentURI;

  /**
   * Whether SourceKit-LSP should ensure that the document's target is prepared before returning build settings.
   *
   * There is a tradeoff whether the target should be prepared: Preparing a target may take significant time but if the
   * target is not prepared, the build settings might eg. refer to modules that haven't been built yet.
   */
  prepareTarget: bool;

  /**
   * If set to `true` and build settings could not be determined within a timeout (see `buildSettingsTimeout` in the
   * SourceKit-LSP configuration file), this request returns fallback build settings.
   *
   * If set to `true` the request only finishes when build settings were provided by the build server.
   */
  allowFallbackSettings: bool
}

/**
 * The kind of options that were returned by the `workspace/_sourceKitOptions` request, ie. whether they are fallback
 * options or the real compiler options for the file.
 */
export namespace SourceKitOptionsKind {
  /**
   * The SourceKit options are known to SourceKit-LSP and returned them.
   */
  export const normal = "normal"

  /**
   * SourceKit-LSP was unable to determine the build settings for this file and synthesized fallback settings.
   */
  export const fallback = "fallback"
}

export interface SourceKitOptionsResult {
  /**
   * The compiler options required for the requested file.
   */
  compilerArguments: string[];

  /**
   * The working directory for the compile command.
   */
  workingDirectory?: string;

  /**
   * Whether SourceKit-LSP was able to determine the build settings or synthesized fallback settings.
   */
  kind: SourceKitOptionsKind;

  /**
   * - `true` If the request requested the file's target to be prepared and the target needed preparing
   * - `false` If the request requested the file's target to be prepared and the target was up to date
   * - `nil`: If the request did not request the file's target to be prepared or the target  could not be prepared for
   * other reasons
   */
  didPrepareTarget?: bool

  /**
   * Additional data that the BSP server returned in the `textDocument/sourceKitOptions` BSP request. This data is not
   * interpreted by SourceKit-LSP.
   */
  data?: LSPAny
}
```

## `workspace/_outputPaths`

New request from the client to the server to retrieve the output paths of a target (see the `buildTarget/outputPaths` BSP request).

This request will only succeed if the build server supports the `buildTarget/outputPaths` request.

> [!IMPORTANT]
> This request is experimental, guarded behind the `output-paths-request` experimental feature, and may be modified or removed in future versions of SourceKit-LSP without notice. Do not rely on it.


- params: `OutputPathsRequest`
- result: `OutputPathsResult`

```ts
export interface OutputPathsRequest {
  /**
   * The target whose output file paths to get.
   */
  target: DocumentURI;

  /**
   * The URI of the workspace to which the target belongs.
   */
  workspace: DocumentURI;
}

export interface OutputPathsResult {
  /**
   * The output paths for all source files in the target
   */
  outputPaths: string[];
}
```

## `workspace/getReferenceDocument`

Request from the client to the server asking for contents of a URI having a custom scheme.
For example: "sourcekit-lsp:"

Enable the experimental client capability `"workspace/getReferenceDocument"` so that the server responds with reference document URLs for certain requests or commands whenever possible.

- params: `GetReferenceDocumentParams`

- result: `GetReferenceDocumentResponse`

```ts
export interface GetReferenceDocumentParams {
  /**
   * The `DocumentUri` of the custom scheme url for which content is required
   */
  uri: DocumentUri;
}

/**
 * Response containing `content` of `GetReferenceDocumentRequest`
 */
export interface GetReferenceDocumentResult {
  content: string;
}
```

## `workspace/peekDocuments`

Request from the server to the client to show the given documents in a "peeked" editor.

This request is handled by the client to show the given documents in a "peeked" editor (i.e. inline with / inside the editor canvas).

It requires the experimental client capability `"workspace/peekDocuments"` to use.

- params: `PeekDocumentsParams`
- result: `PeekDocumentsResult`

```ts
export interface PeekDocumentsParams {
  /**
   * The `DocumentUri` of the text document in which to show the "peeked" editor
   */
  uri: DocumentUri;

  /**
   * The `Position` in the given text document in which to show the "peeked editor"
   */
  position: Position;

  /**
   * An array `DocumentUri` of the documents to appear inside the "peeked" editor
   */
  locations: DocumentUri[];
}

/**
 * Response to indicate the `success` of the `PeekDocumentsRequest`
 */
export interface PeekDocumentsResult {
  success: boolean;
}
```

## `workspace/synchronize`

Request from the client to the server to wait for SourceKit-LSP to handle all ongoing requests and, optionally, wait for background activity to finish.

This method is intended to be used in automated environments which need to wait for background activity to finish before executing requests that rely on that background activity to finish. Examples of such cases are:
 - Automated tests that need to wait for background indexing to finish and then checking the result of request results
 - Automated tests that need to wait for requests like file changes to be handled and checking behavior after those have been processed
 - Code analysis tools that want to use SourceKit-LSP to gather information about the project but can only do so after the index has been loaded

Because this request waits for all other SourceKit-LSP requests to finish, it limits parallel request handling and is ill-suited for any kind of interactive environment. In those environments, it is preferable to quickly give the user a result based on the data that is available and (let the user) re-perform the action if the underlying index data has changed.

- params: `SynchronizeParams`
- result: `void`

```ts
export interface SynchronizeParams {
  /**
   * Wait for the build server to have an up-to-date build graph by sending a `workspace/waitForBuildSystemUpdates` to
   * it.
   *
   * This is implied by `index = true`.
   *
   * This option is experimental, guarded behind the `synchronize-for-build-system-updates` experimental feature, and
   * may be modified or removed in future versions of SourceKit-LSP without notice. Do not rely on it.
   */
  buildServerUpdates?: bool;

  /**
   *  Wait for the build server to update its internal mapping of copied files to their original location.
   *
   * This option is experimental, guarded behind the `synchronize-copy-file-map` experimental feature, and may be
   * modified or removed in future versions of SourceKit-LSP without notice. Do not rely on it.
   */
  copyFileMap?: bool;

  /**
   * Wait for background indexing to finish and all index unit files to be loaded into indexstore-db.
   */
  index?: bool;
}
```

## `workspace/tests`

New request that returns symbols for all the test classes and test methods within the current workspace.

- params: `WorkspaceTestsParams`
- result: `TestItem[]`

```ts
export interface WorkspaceTestsParams {}
```

## `workspace/triggerReindex`

New request to re-index all files open in the SourceKit-LSP server.

Users should not need to rely on this request. The index should always be updated automatically in the background. Having to invoke this request means there is a bug in SourceKit-LSP's automatic re-indexing. It does, however, offer a workaround to re-index files when such a bug occurs where otherwise there would be no workaround.


- params: `TriggerReindexParams`
- result: `void`

```ts
export interface TriggerReindexParams {}
```

## Languages

Added a new language with the identifier `tutorial` to support the `*.tutorial` files that
Swift DocC uses to define tutorials and tutorial overviews in its documentation catalogs.
It is expected that editors send document events for `tutorial` and `markdown` files if
they wish to request information about these files from SourceKit-LSP.
