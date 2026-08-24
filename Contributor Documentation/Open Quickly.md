# Open Quickly

Open Quickly is a feature that lets editors provide fast symbol navigation across the entire workspace, including
symbols defined in SDK `.swiftinterface` files. It is built on four LSP extensions that work together in a four-phase
flow.

## LSP Extensions

### `sourcekit/workspace/symbolNames` — Discovery

Returns the flat list of every symbol name currently in the workspace index. The client uses this list to drive its
search UI (fuzzy matching, prefix filtering, etc.).

```
→ WorkspaceSymbolNamesRequest {}
← WorkspaceSymbolNamesResponse {
    names: ["String", "Array", "Dictionary", "MyViewController", ...]
  }
```

### `sourcekit/workspace/symbolInfo` — Resolution

Given a list of names selected by the client after searching, returns structured location information for each name.
Unlike the standard `workspace/symbol` request (which maps a query string to matching symbols), this request takes
exact names and returns all occurrences.

The shape of each result item depends on the symbol's origin:

**Source-file symbols** — returned as `SymbolInformation` with a `file://` URI and the range from the index.

```
→ WorkspaceSymbolInfoRequest { names: ["MyViewController"] }
← WorkspaceSymbolInfoResponse {
    results: [
      SymbolInformation {
        name: "MyViewController",
        kind: .class,
        location: Location {
          uri: "file:///path/to/MyViewController.swift",
          range: { line: 3, character: 0 }
        }
      }
    ]
  }
```

**SDK/stdlib symbols** — returned as `WorkspaceSymbol` with `location: .uri(sourcekit-lsp:// URL)` (no range) and a
`data` payload. The `data` is a `SourceKitWorkspaceSymbolData` that clients decode via `WorkspaceSymbol.sourceKitData`,
carrying the symbol's USR, the `.swiftinterface`/`.swiftmodule` path (`interfaceURI`), and the fully-qualified module
name (`moduleName`, e.g. `Swift.String`) that clients can use to render the candidate. The URI is a
fully-parameterized `sourcekit-lsp://generated-swift-interface/` reference-document URL: `workspaceSymbol/resolve`
fills in its range and `workspace/getReferenceDocument` returns its content. This form is emitted when the client
advertises **both** generated-interface reference documents (`GetReferenceDocumentRequest`) and
`workspaceSymbol/resolve` support (see [Client Capabilities](#client-capabilities)).

```
→ WorkspaceSymbolInfoRequest { names: ["String"] }
← WorkspaceSymbolInfoResponse {
    results: [
      WorkspaceSymbol {
        name: "String",
        kind: .struct,
        location: { uri: "sourcekit-lsp://generated-swift-interface/Swift.String.swiftinterface?moduleName=Swift&groupName=String&sourcekitdDocument=Swift.String.12345678&buildSettingsFrom=file:///path/to/Sources/main.swift" },
        data: {
          "usr": "s:SS",
          "interfaceURI": "file:///path/to/Swift.swiftmodule/arm64-apple-macosx.swiftinterface",
          "moduleName": "Swift.String"
        }
      }
    ]
  }
```

Without those capabilities, the raw `file://` URI of the `.swiftinterface` or `.swiftmodule` file from the index
record is returned as `SymbolInformation` instead.

> [!NOTE]
> The `data` payload is a typed SourceKit-LSP API (`SourceKitWorkspaceSymbolData`): clients should decode it via
> `WorkspaceSymbol.sourceKitData` rather than reading raw JSON keys.

The response is a flat array of `WorkspaceSymbolItem` values. Each item carries the symbol name in its `name` field.

### `workspaceSymbol/resolve` — Range Resolution

Fills in the range of a `WorkspaceSymbol` returned by `sourcekit/workspace/symbolInfo`. The server parses
`moduleName`, `groupName`, and `buildSettingsFrom` from the location URI, reads `usr` from `sourceKitData`,
opens the generated Swift interface for the symbol's module, finds the symbol's position using the USR, and returns
the same symbol with `location` upgraded from a URI-only location to a full `Location` (URI + range).

```
→ WorkspaceSymbolResolveRequest {
    workspaceSymbol: WorkspaceSymbol {
      name: "String",
      kind: .struct,
      location: { uri: "sourcekit-lsp://generated-swift-interface/Swift.String.swiftinterface?moduleName=Swift&groupName=String&sourcekitdDocument=Swift.String.12345678&buildSettingsFrom=file:///path/to/Sources/main.swift" },
      data: { "usr": "s:SS" }
    }
  }
← WorkspaceSymbol {
    name: "String",
    kind: .struct,
    location: Location {
      uri: "sourcekit-lsp://generated-swift-interface/Swift.String.swiftinterface?moduleName=Swift&groupName=String&sourcekitdDocument=Swift.String.12345678&buildSettingsFrom=file:///path/to/Sources/main.swift",
      range: { line: 42, character: 14 }
    }
  }
```

The client must treat the `sourcekit-lsp://` URI as **opaque** — it should not parse or extract information from the
query parameters. The path component (e.g. `Swift.String.swiftinterface`) may be used as the editor tab title. The URI
is otherwise only valid as an input to `workspace/getReferenceDocument`; its query parameter structure is an
implementation detail subject to change.

### `workspace/getReferenceDocument` — Content Retrieval

Fetches the text content of a reference document URI (e.g. a generated Swift interface). This is a pure content
provider — it returns the document text and nothing else.

```
→ GetReferenceDocumentRequest { uri: "sourcekit-lsp://generated-swift-interface/...?sourcekitdDocument=...&..." }
← GetReferenceDocumentResponse {
    content: "// Swift.String\n...\npublic struct String { ... }"
  }
```

The URI passed here is the same one carried by the `WorkspaceSymbol` from `sourcekit/workspace/symbolInfo`; the client
does not need to have resolved the range first.

## Workflow

```
Client                                            Server
  │                                                  │
  │── sourcekit/workspace/symbolNames ──────────────▶│
  │◀─ { ["String", "Array", ...] } ──────────────────│
  │                                                  │
  │  [user types "Str"]                              │
  │                                                  │
  │── sourcekit/workspace/symbolInfo                 │
  │     {["String", "Stride", ...]} ────────────────▶│
  │◀─ [WorkspaceSymbol] ─────────────────────────────│
  │     (location: "sourcekit-lsp://...")            │
  │                                                  │
  │  [user selects "String"]                         │
  │                                                  │
  │── workspaceSymbol/resolve ──────────────────────▶│
  │◀─ WorkspaceSymbol                                │
  │     (location: uri + range) ─────────────────────│
  │                                                  │
  │── workspace/getReferenceDocument ───────────────▶│
  │◀─ { content: "..." } ────────────────────────────│
  │                                                  │
  │  [open tab, scroll to range.start]               │
```

1. **Discovery** — fetch all names; client filters locally.
2. **Resolution** — send matching name(s) to populate the search result list; server returns symbol details (kind,
   container name, location) for display.
   - Source symbols: `SymbolInformation` with a `file://` URI and exact position. No further steps required.
   - SDK/stdlib symbols: `WorkspaceSymbol` with a `location: .uri(sourcekit-lsp:// URL)` (no range) and a
     `SourceKitWorkspaceSymbolData` payload in `data`, when the client advertises the required capabilities. Otherwise
     falls back to `SymbolInformation` with the raw `file://` interface URI.
3. **Range resolution** — call `workspaceSymbol/resolve` with the selected `WorkspaceSymbol` to open the generated
   interface and resolve the symbol position. The server fills in `location.range`.
4. **Content retrieval** — fetch the generated interface text. The editor scrolls to `location.range.start` from the
   resolve step.

## `sourcekit-lsp://` URI for SDK/stdlib Symbols

The location URI for an SDK/stdlib `WorkspaceSymbol` is a fully-parameterized
`sourcekit-lsp://generated-swift-interface/` URL, built at `sourcekit/workspace/symbolInfo` time. The `data` field
carries the USR and, for display, the interface path and module name.

### URL Structure

```
sourcekit-lsp://<document-type>/<display-name>?<parameters>
```

| Component | Value for generated interfaces |
|---|---|
| `document-type` | `generated-swift-interface` |
| `display-name` | Human-readable filename shown in the editor tab/breadcrumb (e.g. `Swift.String.swiftinterface`). **Not used when parsing the URI** — all functional data is in the query parameters. |
| `moduleName` | Top-level module name (e.g. `Swift`) |
| `groupName` | Sub-module / group within the module, if any (e.g. `String`) |
| `sourcekitdDocument` | Passed as `keys.name` to sourcekitd's `editor.open.interface` request — the buffer handle by which sourcekitd tracks the open interface. Derived as `<moduleName>.<groupName>.<buildSettingsHash>` (e.g. `Swift.String.12345678`) to make the buffer name unique per build-settings context. It is derived identically at the `symbolInfo` emission site and the open site so both refer to the same sourcekitd document. |
| `buildSettingsFrom` | URI of a real source file in the workspace, obtained via `mainFiles(containing:)`. Used to derive build settings for the generated interface. |

The index module name (e.g. `Swift.String`) is split on the first `.` to derive `moduleName` and `groupName`; if there
is no dot (e.g. `Foundation`), `groupName` is absent.

### `display-name` derivation

| `moduleName` | `groupName` | `display-name` |
|---|---|---|
| `Swift` | `String` | `Swift.String.swiftinterface` |
| `Foundation` | `NSURLSession` | `Foundation.NSURLSession.swiftinterface` |
| `Foundation` | _(none)_ | `Foundation.swiftinterface` |

If `groupName` contains `/` (possible for nested groups), the slashes are replaced with `.` in the display name.

### Example URI

**`Swift.String`** (USR `s:SS`):

```
sourcekit-lsp://generated-swift-interface/Swift.String.swiftinterface
  ?moduleName=Swift
  &groupName=String
  &sourcekitdDocument=Swift.String.12345678
  &buildSettingsFrom=file:///path/to/MyProject/Sources/main.swift
```

## Client Capabilities

The `WorkspaceSymbol`/`.uri` path in `sourcekit/workspace/symbolInfo` is gated on the client advertising **both** of
the following. When either is missing, `sourcekit/workspace/symbolInfo` falls back to `SymbolInformation` with the raw
`file://` URI from the index record.

- `GetReferenceDocumentRequest` support (an experimental client capability) — signals that the client can open the
  `sourcekit-lsp://` reference document via `workspace/getReferenceDocument`.
- `ClientCapabilities.workspace.symbol.resolveSupport.properties` containing `"location"` or `"location.range"` (LSP
  3.17) — signals that the client can call `workspaceSymbol/resolve` to obtain a range-bearing location.

The server advertises its side of the contract by reporting `workspaceSymbolProvider` with `resolveProvider: true`.

## Notes

- _User_ binary `.swiftmodule` files compiled without `-index-store-path` are **not** indexed — there is no index
  store record for them, so their symbols do not appear in `sourcekit/workspace/symbolNames` or
  `sourcekit/workspace/symbolInfo`.
- _System/non-user_ binary modules (`isNonUserModule() == true`) **are** indexed by the Swift compiler when
  `indexSystemModules` is enabled (`IndexRecord.cpp: emitDataForSwiftSerializedModule`):
  - *Resilient* system modules: the compiler reloads from the adjacent `.swiftinterface` before indexing. If no
    interface is available, the module is skipped entirely.
  - *Non-resilient* system modules and the stdlib: indexed directly from the binary; symbol locations in the index
    point to the `.swiftmodule` file.
- Both `.swiftinterface` and `.swiftmodule` location paths are handled identically in `workspaceSymbolItem` — both
  produce a `WorkspaceSymbol` with a `sourcekit-lsp://generated-swift-interface` location URI and a `data` dictionary
  with the USR, when the client has the required capabilities. sourcekitd can synthesize a textual interface from
  either form.
- The standard `workspace/symbol` request is unaffected: it filters out system symbols, so none of its results point
  into a generated interface.
