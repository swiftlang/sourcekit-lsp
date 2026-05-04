# Open Quickly

Open Quickly is a feature that lets editors provide fast symbol navigation across the entire workspace, including symbols defined in SDK `.swiftinterface` files. It is built on four LSP extensions that work together in a four-phase flow.

## LSP Extensions

### `sourcekit/workspace/symbolNames` — Discovery

Returns the flat list of every symbol name currently in the workspace index. The client uses this list to drive its search UI (fuzzy matching, prefix filtering, etc.).

```
→ WorkspaceSymbolNamesRequest {}
← WorkspaceSymbolNamesResponse {
    names: ["String", "Array", "Dictionary", "MyViewController", ...]
  }
```

### `sourcekit/workspace/symbolInfo` — Resolution

Given a list of names selected by the client after searching, returns structured location information for each name. Unlike the standard `workspace/symbol` request (which maps a query string to matching symbols), this request takes exact names and returns all occurrences.

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

**SDK/stdlib symbols** — returned as `WorkspaceSymbol` with `location: .uri(file:// URL)` (no range) pointing to the `.swiftinterface` or `.swiftmodule` file from the index record, when the client advertises `workspace.symbol.resolveSupport`. The fully-qualified module name (e.g. `Swift.String`) is appended as a `?module=` query parameter on the location URL so clients can derive a display path without inspecting the `data` dictionary. The symbol's USR is stored in the `data` dictionary. The client must call `workspaceSymbol/resolve` to obtain the exact location within the generated interface.

```
→ WorkspaceSymbolInfoRequest { names: ["String"] }
← WorkspaceSymbolInfoResponse {
    results: [
      WorkspaceSymbol {
        name: "String",
        kind: .struct,
        location: { uri: "file:///path/to/Swift.swiftmodule/arm64-apple-macosx.swiftinterface?module=Swift.String" },
        data: { "usr": "s:SS" }
      }
    ]
  }
```

Without that capability, the raw `file://` URI of the `.swiftinterface` or `.swiftmodule` file from the index record is returned as `SymbolInformation` instead.

The response is a flat array of `WorkspaceSymbolItem` values. Each item carries the symbol name in its `name` field.

### `workspaceSymbol/resolve` — Location Resolution

Resolves the lazy location of a `WorkspaceSymbol` returned by `sourcekit/workspace/symbolInfo`. The server parses `moduleName` and `groupName` from the `?module=` query parameter of the location URL, reads `usr` from the `data` dictionary, opens the generated Swift interface for the symbol's module, finds the symbol's position using the USR, and returns the same symbol with `location` replaced by a full `Location` (URI + range).

```
→ WorkspaceSymbolResolveRequest {
    workspaceSymbol: WorkspaceSymbol {
      name: "String",
      kind: .struct,
      location: { uri: "file:///path/to/Swift.swiftmodule/arm64-apple-macosx.swiftinterface?module=Swift.String" },
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

The resolved URI is a fully-parameterized `sourcekit-lsp://generated-swift-interface/` URL containing `sourcekitdDocument` and `buildSettingsFrom` derived from a real source file in the workspace via `mainFiles(containing:)`.

The client must treat the resolved `sourcekit-lsp://` URI as **opaque** — it should not parse or extract information from the query parameters. The path component (e.g. `Swift.String.swiftinterface`) may be used as the editor tab title. The URI is otherwise only valid as an input to `workspace/getReferenceDocument`; its query parameter structure is an implementation detail subject to change.

### `workspace/getReferenceDocument` — Content Retrieval

Fetches the text content of a reference document URI (e.g. a generated Swift interface). This is a pure content provider — it returns the document text and nothing else.

```
→ GetReferenceDocumentRequest { uri: "sourcekit-lsp://generated-swift-interface/...?sourcekitdDocument=...&..." }
← GetReferenceDocumentResponse {
    content: "// Swift.String\n...\npublic struct String { ... }"
  }
```

The URI passed here must be a fully resolved URI (with `sourcekitdDocument` set), as returned by `workspaceSymbol/resolve`.

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
  │     (location: "file://...?module=Swift.String") │
  │                                                  │
  │  [user selects "String"]                         │
  │                                                  │
  │── workspaceSymbol/resolve ──────────────────────▶│
  │◀─ WorkspaceSymbol                                │
  │     (url: "sourcekit-lsp://...", range: ...) ────│
  │                                                  │
  │── workspace/getReferenceDocument ───────────────▶│
  │◀─ { content: "..." } ────────────────────────────│
  │                                                  │
  │  [open tab, scroll to range.start]               │
```

1. **Discovery** — fetch all names; client filters locally.
2. **Resolution** — send matching name(s) to populate the search result list; server returns symbol details (kind, container name, location) for display.
   - Source symbols: `SymbolInformation` with a `file://` URI and exact position. No further steps required.
   - SDK/stdlib symbols: `WorkspaceSymbol` with `location: .uri(file:// URL?module=...)` pointing to the module file and the USR in `data["usr"]`, when the client advertises `workspace.symbol.resolveSupport`. Otherwise falls back to `SymbolInformation` with the raw `file://` URI.
3. **Location resolution** — call `workspaceSymbol/resolve` with the selected `WorkspaceSymbol` to open the generated interface and resolve the symbol position. The server synthesizes the final `sourcekit-lsp://` URI and fills in `location.range`.
4. **Content retrieval** — fetch the generated interface text. The editor scrolls to `location.range.start` from the resolve step.

## Pre-resolve Location Design for SDK/stdlib Symbols

When `sourcekit/workspace/symbolInfo` returns a `WorkspaceSymbol` for an SDK or stdlib symbol, the location is a `file://` URL pointing to the `.swiftinterface` or `.swiftmodule` file recorded in the index, with the fully-qualified module name appended as a `?module=` query parameter. The `data` field carries only the USR. There is no special URI scheme to parse.

`DocumentURI` equality and hashing use the filesystem path (via `withUnsafeFileSystemRepresentation`), which strips query parameters, so the URL with `?module=` compares equal to the clean path for all index and build-system lookups.

### `WorkspaceSymbol` fields

| Field | Value |
|---|---|
| `location` | `.uri(LocationURI)` — a `file://` URL to the `.swiftinterface` or `.swiftmodule` file, with `?module=<fullyQualifiedModuleName>` appended (e.g. `?module=Swift.String`) |
| `data["usr"]` | Unified Symbol Reference string (e.g. `"s:SS"`) — used by `workspaceSymbol/resolve` to pinpoint the symbol's line/column within the generated interface |

### `?module=` query parameter

The `?module=` value is the fully-qualified dotted module name recorded in the index (e.g. `Swift.String`, `Foundation`). The server appends it when constructing the location URL:

```swift
var urlComponents = URLComponents(string: moduleFileURI.stringValue)!
urlComponents.queryItems = [URLQueryItem(name: "module", value: fullModuleName)]
```

`workspaceSymbol/resolve` splits the value on the first `.` to derive `moduleName` and `groupName` for sourcekitd:

```swift
// fullModuleName = "Swift.String"
moduleName = "Swift"    // passed to openGeneratedInterface
groupName  = "String"   // passed to openGeneratedInterface
```

If there is no dot (e.g. `Foundation`), `groupName` is absent.

### Example pre-resolve `WorkspaceSymbol`

**`Swift.String`** (USR `s:SS`)

```
WorkspaceSymbol {
  name: "String",
  kind: .struct,
  location: .uri("file:///path/to/Swift.swiftmodule/arm64-apple-macosx.swiftinterface?module=Swift.String"),
  data: { "usr": "s:SS" }
}
```

### `workspaceSymbol/resolve` transformation

The resolve step parses the location URL, extracts the clean file path (query excluded via `urlComponents.path`) for `mainFiles(containing:)`, then opens the generated interface via sourcekitd:

1. Parse `?module=Swift.String` from `uriOnly.uri.arbitrarySchemeURL`; split at first `.` → `moduleName`, `groupName`
2. Read `usr` from `data["usr"]`
3. Look up a real source file via `mainFiles(containing: moduleFileURI)`, sorted by URL string for determinism; pick `.first`
4. Call `openGeneratedInterface(document: primaryFile, moduleName:, groupName:, symbolUSR:)`
5. Return the symbol with `location` replaced by a full `Location` (resolved `sourcekit-lsp://` URI + range)

## `sourcekit-lsp://` URI for Resolved Locations

After `workspaceSymbol/resolve`, the location URI is a fully-parameterized `sourcekit-lsp://generated-swift-interface/` URL.

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
| `sourcekitdDocument` | Passed as `keys.name` to sourcekitd's `editor.open.interface` request — the buffer handle by which sourcekitd tracks the open interface. Synthesized by `workspaceSymbol/resolve` as `<moduleName>.<groupName>.<buildSettingsHash>` (e.g. `Swift.String.12345678`) to make the buffer name unique per build-settings context. |
| `buildSettingsFrom` | URI of a real source file in the workspace, obtained via `mainFiles(containing:)`. Used to derive build settings for the generated interface. |

### `display-name` derivation

| `moduleName` | `groupName` | `display-name` |
|---|---|---|
| `Swift` | `String` | `Swift.String.swiftinterface` |
| `Foundation` | `NSURLSession` | `Foundation.NSURLSession.swiftinterface` |
| `Foundation` | _(none)_ | `Foundation.swiftinterface` |

If `groupName` contains `/` (possible for nested groups), the slashes are replaced with `.` in the display name.

### Example resolved URI

**`Swift.String`** after `workspaceSymbol/resolve`:

```
sourcekit-lsp://generated-swift-interface/Swift.String.swiftinterface
  ?moduleName=Swift
  &groupName=String
  &sourcekitdDocument=Swift.String.12345678
  &buildSettingsFrom=file:///path/to/MyProject/Sources/main.swift
```

## Notes

- _User_ binary `.swiftmodule` files compiled without `-index-store-path` are **not** indexed — there is no index store record for them, so their symbols do not appear in `sourcekit/workspace/symbolNames` or `sourcekit/workspace/symbolInfo`.
- _System/non-user_ binary modules (`isNonUserModule() == true`) **are** indexed by the Swift compiler when `indexSystemModules` is enabled (`IndexRecord.cpp: emitDataForSwiftSerializedModule`):
  - *Resilient* system modules: the compiler reloads from the adjacent `.swiftinterface` before indexing. If no interface is available, the module is skipped entirely.
  - *Non-resilient* system modules and the stdlib: indexed directly from the binary; symbol locations in the index point to the `.swiftmodule` file.
- Both `.swiftinterface` and `.swiftmodule` location paths are handled identically in `workspaceSymbolItem` — both produce a `WorkspaceSymbol` with a `file://` location URI (carrying `?module=`) and a `data` dictionary with the USR, when the client has the required capabilities. sourcekitd can synthesize a textual interface from either form.
- One client capability gates the `WorkspaceSymbol`/`.uri` path in `sourcekit/workspace/symbolInfo`:
  - `ClientCapabilities.workspace.symbol.resolveSupport.properties` containing `"location"` or `"location.range"` (LSP 3.17) — signals that the client can call `workspaceSymbol/resolve` to obtain a range-bearing location.
  - Without it, `sourcekit/workspace/symbolInfo` returns `SymbolInformation` with the raw `file://` URI from the index record.
- The resolved location URI from `workspaceSymbol/resolve` uses a `sourcekit-lsp://generated-swift-interface/` scheme when the client advertises `GetReferenceDocumentRequest` support, or a temp `file://` path otherwise. Both forms can be used to open the generated interface.
