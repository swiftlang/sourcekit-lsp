# Refactoring Actions

SourceKit-LSP exposes refactoring capabilities through the LSP Code Actions API. When you trigger code actions in your editor (typically via the lightbulb icon or keyboard shortcut), SourceKit-LSP returns available refactorings for the current selection.

## How to Invoke Refactoring Actions

Code actions show up automatically in LSP-compatible editors. Common ways to trigger them:

- **VS Code**: `Cmd+.` (macOS) or `Ctrl+.` (Windows/Linux)
- **Neovim** (with nvim-lspconfig): `:lua vim.lsp.buf.code_action()`

The specific refactorings available depend on what code is selected or where the cursor is positioned.

## Available Refactorings

SourceKit-LSP provides refactoring actions from multiple sources:

### Semantic Refactorings (via sourcekitd)

These refactorings require full semantic analysis of the code and are provided by the Swift compiler's sourcekitd.

#### Cursor-Based Refactorings

These are triggered when the cursor is on a specific location:

| Action | Description |
|--------|-------------|
| **Add Missing Protocol Requirements** | Adds stubs for unimplemented protocol requirements |
| **Expand Default** | Expands a `default` case in a switch statement |
| **Expand Switch Cases** | Expands a switch to include all enum cases |
| **Localize String** | Wraps a string literal with `NSLocalizedString` |
| **Simplify Long Number Literal** | Simplifies a long number literal |
| **Collapse Nested If Statements** | Combines nested if statements into one |
| **Convert To Do/Catch** | Converts a throwing expression to do/catch |
| **Convert To Trailing Closure** | Converts a closure argument to trailing closure syntax |
| **Generate Memberwise Initializer** | Creates an initializer with all stored properties |
| **Add Equatable Conformance** | Generates `Equatable` conformance |
| **Add Explicit Codable Implementation** | Generates explicit `Codable` encode/decode methods |
| **Convert Call to Async Alternative** | Converts a completion handler call to async/await |
| **Convert Function to Async** | Converts a function with completion handler to async |
| **Add Async Alternative** | Adds an async version of a completion handler function |
| **Add Async Wrapper** | Adds an async wrapper around a completion handler function |
| **Expand Macro** | Shows the expanded form of a macro |
| **Inline Macro** | Inlines the expansion of a freestanding macro |

#### Range-Based Refactorings

These are triggered when you select a range of code:

| Action | Description |
|--------|-------------|
| **Extract Expression** | Extracts an expression into a local variable |
| **Extract Method** | Extracts selected statements into a new function |
| **Extract Repeated Expression** | Extracts a repeated expression into a variable |
| **Move To Extension** | Moves selected members to an extension |
| **Convert to String Interpolation** | Converts string concatenation to interpolation |
| **Expand Ternary Expression** | Expands a ternary `?:` to an if/else statement |
| **Convert To Ternary Expression** | Converts an if/else to a ternary expression |
| **Convert To Guard Expression** | Converts an if-let to a guard-let |
| **Convert To IfLet Expression** | Converts a guard-let to an if-let |
| **Convert To Computed Property** | Converts a stored property to a computed property |
| **Convert To Switch Statement** | Converts if/else chains to a switch statement |

### Syntactic Refactorings (via SwiftSyntax)

These work purely on syntax and don't require compilation:

| Action | Description | Trigger |
|--------|-------------|---------|
| **Add digit separators** | Converts `1000000` to `1_000_000` | Cursor on an integer literal |
| **Remove digit separators** | Converts `1_000_000` to `1000000` | Cursor on an integer literal with separators |
| **Convert integer literal** | Converts between decimal, hex, octal, binary | Cursor on an integer literal |
| **Convert to minimal # count** | Simplifies raw string delimiters like `#"..."#` | Cursor on a raw string literal |
| **Migrate to shorthand 'if let'** | Converts `if let x = x` to `if let x` | Cursor on an if-let statement |
| **Expand 'some' parameters** | Converts opaque types to generics | Cursor on a function with `some` parameters |
| **Convert to computed property** | Changes zero-parameter function to computed property | Cursor on a function with no parameters |
| **Convert to function** | Changes computed property to zero-parameter function | Cursor on a computed property |
| **Add documentation** | Generates a doc comment stub | Cursor on a declaration |
| **Create Codable structs from JSON** | Generates Swift structs from JSON data | Cursor on JSON content in a Swift file |
| **Convert String Concatenation to Interpolation** | Converts `"a" + b + "c"` to `"a\(b)c"` | Cursor on a string concatenation |

### Package.swift Manifest Editing

When editing a `Package.swift` file, additional refactorings are available:

| Action | Description | Trigger |
|--------|-------------|---------|
| **Add library target** | Adds a new library target to the package | Cursor on a `.target()` declaration |
| **Add test target (Swift Testing)** | Adds a test target using Swift Testing | Cursor on a `.target()` declaration |
| **Add product to export this target** | Creates a product entry for the target | Cursor on a `.target()` declaration |

### Source Organization

| Action | Description | Trigger |
|--------|-------------|---------|
| **Remove Unused Imports** | Removes import statements that aren't needed | Cursor on an import declaration |

> **Note**: Remove Unused Imports works by iteratively removing imports and checking if the file still compiles. It's only offered when the file has no existing errors.

## Quick Fixes

Beyond refactorings, SourceKit-LSP also provides quick fixes for diagnostics:

- **Fix-Its from the compiler**: Automatic corrections for compile errors and warnings
- **Fix-Its from SwiftSyntax**: Syntax-level corrections for parsing issues

Quick fixes appear alongside refactorings in the code actions menu but have the `quickfix` kind rather than `refactor`.

## Editor Support

Most LSP-compatible editors filter code actions by kind. Make sure your editor requests both `refactor` and `quickfix` kinds to see all available actions. You can verify this in your editor's LSP client configuration.

### Checking Available Actions

If you're not seeing expected refactorings, you can:

1. Check that code actions are supported in your client capabilities
2. Verify the cursor position matches the expected trigger location
3. Look at the SourceKit-LSP logs for any errors during code action requests

## Adding New Refactorings

Refactoring capabilities come from two places:

1. **sourcekitd**: Part of the Swift toolchain compiler infrastructure
2. **SwiftSyntax**: The `swift-syntax` library's `SwiftRefactor` module

To add purely syntactic refactorings, you can contribute to [swift-syntax](https://github.com/swiftlang/swift-syntax). Semantic refactorings require changes to [sourcekitd](https://github.com/swiftlang/swift).
