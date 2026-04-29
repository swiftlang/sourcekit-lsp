# Jump to Definition

Jump to definition for SDK/stdlib symbols works by generating a
textual Swift interface on demand and returning a `sourcekit-lsp://`
URI that the client can fetch via `workspace/getReferenceDocument`.

## Requests Involved

| Request | Direction | Purpose |
|---|---|---|
| `textDocument/definition` | Client → Server | Resolve the symbol under the cursor to a location |
| `workspace/getReferenceDocument` | Client → Server | Fetch the content of a `sourcekit-lsp://` URI |

`workspace/getReferenceDocument` is a SourceKit-LSP extension. The
client must advertise support in `ClientCapabilities.experimental`:

```json
{ "workspace/getReferenceDocument": { "supported": true } }
```

Without this capability the server writes the interface to a temporary
file and returns a `file://` URI instead.

## Workflow

```
Client                                    Server
  │                                          │
  │── textDocument/definition ──────────────▶│
  │◀─ Location {                             │
  │     uri: "sourcekit-lsp://...",          │
  │     range: { line: 42, character: 14 }   │
  │   }                                      │
  │                                          │
  │── workspace/getReferenceDocument ───────▶│
  │◀─ { content: "..." } ────────────────────│
  │                                          │
  │  [open tab, scroll to range]             │
```

1. **Definition** — the client requests the definition of the symbol
   at the cursor. For source-defined symbols the server returns a
   `file://` URI with the exact source location. For SDK/stdlib
   symbols it returns a `sourcekit-lsp://` URI and sets `range` to
   the symbol's position within the generated interface (computed
   server-side via `editor.find_usr`).
2. **Content retrieval** — the client fetches the generated interface
   via `workspace/getReferenceDocument` to display its content. The
   client scrolls to `range` from the definition response — `symbolPosition`
   is not used here since the position is already known from step 1.

## Server-Side Flow

### 1. `textDocument/definition` handling

The server first attempts an index-based lookup
(`indexBasedDefinition`). For system/SDK symbols the index record
points to a `.swiftinterface` or `.swiftmodule` file, so the handler
calls:

```
definitionInInterface(
  moduleName:    <from SymbolDetails.systemModule>,
  groupName:     <from SymbolDetails.systemModule>,
  symbolUSR:     <symbol.usr>,
  originatorUri: <the file the cursor is in>
)
```

### 2. `openGeneratedInterface`

`definitionInInterface` delegates to
`SwiftLanguageService.openGeneratedInterface`, which:

1. Constructs a fully-resolved `GeneratedInterfaceDocumentURLData`
   using `init(moduleName:groupName:primaryFile:)`:
   - `sourcekitdDocumentName` is synthesised as
     `<moduleName>.<groupName>.<hash>` where `hash` is
     `abs(buildSettingsFile.stringValue.hashValue)`.
   - `buildSettingsFrom` is set to `originatorUri.buildSettingsFile`
     — the build settings file of the **requesting source file**, not
     the module file. This ensures sourcekitd uses the same compiler
     arguments as the file that triggered the request.
2. Calls `generatedInterfaceManager.position(ofUsr:in:)` to find the
   symbol's position within the generated interface (see below).
3. Returns `GeneratedInterfaceDetails(uri: sourcekit-lsp://...,
   position: <symbol position>)`.

The URI has no USR fragment. The position is returned separately and
used as `Location.range` in the definition response.

### 3. Interface generation and caching

`GeneratedInterfaceManager` opens the interface in sourcekitd via
`editor.open.interface`:

```
keys.name:                 "<moduleName>.<groupName>.<hash>"
keys.moduleName:           "<moduleName>"
keys.groupName:            "<groupName>"          // if present
keys.synthesizedExtension: 1
keys.compilerArgs:         [... compiler arguments from build settings ...]
```

The resulting `sourceText` is cached in memory keyed by
`sourcekitdDocumentName`. Subsequent requests for the same module +
build context reuse the cached snapshot.

### 4. Symbol position within the interface

`GeneratedInterfaceManager.position(ofUsr:in:)` sends
`editor.find_usr` to sourcekitd:

```
keys.sourceFile: "<sourcekitdDocumentName>"
keys.usr:        "<symbolUSR>"
```

sourcekitd returns a byte offset, which is converted to a 0-based
`Position` via `DocumentSnapshot.positionOf(utf8Offset:)`.

### 5. URI returned to the client

The `sourcekit-lsp://` URI is fully resolved — `sourcekitdDocument`
is always present, and there is no USR fragment:

```
sourcekit-lsp://generated-swift-interface/Swift.String.swiftinterface
  ?moduleName=Swift
  &groupName=String
  &sourcekitdDocument=Swift.String.12345678
  &buildSettingsFrom=file:///path/to/main.swift
```

The `range` in the returned `Location` carries the symbol's position
in the interface, so the client knows where to scroll without calling
`workspace/getReferenceDocument` first.

### 6. `workspace/getReferenceDocument` handling

Because the URI is fully resolved (`sourcekitdDocumentName != nil`)
the server skips the stub-resolution path and goes straight to the
language service:

```swift
primaryLanguageService(for: buildSettingsUri, ...).getReferenceDocument(req)
```

`SwiftLanguageService.getReferenceDocument` retrieves the cached
interface snapshot. Since the URI carries no USR fragment,
`symbolPosition` in the response is `nil` — the client uses
`Location.range` from the definition response instead.
