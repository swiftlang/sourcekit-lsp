# Refactoring Actions

SourceKit-LSP exposes refactoring capabilities through the LSP Code Actions API. When you trigger code actions in your editor (typically via the lightbulb icon or keyboard shortcut), SourceKit-LSP returns available refactorings for the current selection.

## How to Invoke Refactoring Actions

Code actions show up automatically in LSP-compatible editors. Common ways to trigger them:

- **VS Code**: `Cmd+.` (macOS) or `Ctrl+.` (Windows/Linux)
- **Neovim** (with nvim-lspconfig): `:lua vim.lsp.buf.code_action()`
- **Xcode**: Right-click → Refactor menu

The specific refactorings available depend on what code is selected or where the cursor is positioned.

## Available Refactorings

SourceKit-LSP provides refactoring actions from multiple sources:

### Semantic Refactorings (via sourcekitd)

These refactorings require full semantic analysis of the code:

| Action | Description | Trigger |
|--------|-------------|---------|
| **Extract Method** | Extracts selected statements into a new function | Select a range of complete statements |
| **Localize String** | Wraps a string literal for localization | Cursor inside a string literal |
| **Expand Macro** | Shows the expanded form of a macro | Cursor on a macro invocation |
| **Inline Macro** | Inlines the expansion of a freestanding macro | Cursor on a macro invocation |

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

To add purely syntactic refactorings, you can contribute to [swift-syntax](https://github.com/swiftlang/swift-syntax). Semantic refactorings require changes to [sourcekit](https://github.com/swiftlang/swift).
