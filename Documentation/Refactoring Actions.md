# Refactoring Actions

SourceKit-LSP exposes refactoring capabilities through the LSP Code Actions API. When you trigger code actions in your editor (typically via the lightbulb icon or keyboard shortcut), SourceKit-LSP returns available refactorings for the current selection.

## How to Invoke Refactoring Actions

Code actions show up automatically in LSP-compatible editors. Common ways to trigger them:

- **VS Code**: `Cmd+.` (macOS) or `Ctrl+.` (Windows/Linux)
- **Neovim** (with nvim-lspconfig): `:lua vim.lsp.buf.code_action()`

The specific refactorings available depend on what code is selected or where the cursor is positioned.

## Available Refactorings

### Strings and Literals

| Action | Trigger |
|--------|---------|
| **Localize String** | Cursor on a string literal |
| **Simplify Long Number Literal** | Cursor on a long number literal (e.g. `1_000_000`) |
| **Add digit separators** | Cursor on an integer literal without separators |
| **Remove digit separators** | Cursor on an integer literal with separators |
| **Convert integer literal** | Cursor on an integer literal (converts between decimal, hex, octal, binary) |
| **Convert string literal to minimal number of '#'s** | Cursor on a raw string literal with unnecessary `#` delimiters |
| **Create Codable structs from JSON** | Cursor inside JSON content in a Swift file |
| **Convert to String Interpolation** | Select a string concatenation expression (`"a" + b + "c"`) |

### Control Flow

| Action | Trigger |
|--------|---------|
| **Expand Default** | Cursor on the `default` keyword in a switch over an enum |
| **Expand Switch Cases** | Cursor on the `switch` keyword when switching over an enum with unhandled cases |
| **Collapse Nested If Statements** | Cursor on the `if` keyword of an if-statement that contains only another if statement |
| **Convert To Do/Catch** | Cursor on the `try` keyword of a `try!` expression |
| **Expand Ternary Expression** | Select an assignment where the right-hand side is a ternary expression |
| **Convert To Ternary Expression** | Select an if/else that assigns or returns a value |
| **Convert To Guard Expression** | Select an if-let statement |
| **Convert To IfLet Expression** | Select a guard-let statement |
| **Convert To Switch Statement** | Select an if/else-if chain comparing the same value |
| **Migrate to shorthand 'if let' syntax** | Cursor on `if let x = x` |

### Macros

| Action | Trigger |
|--------|---------|
| **Expand Macro** | Cursor on a macro invocation |
| **Inline Macro** | Cursor on a freestanding macro expansion |

### Functions and Closures

| Action | Trigger |
|--------|---------|
| **Extract Method** | Select an expression or one or more statements |
| **Extract Expression** | Select a single expression |
| **Extract Repeated Expression** | Select a single expression |
| **Convert To Trailing Closure** | Cursor inside a function call where the last argument is a non-trailing closure |
| **Convert to computed property** | Cursor on a zero-parameter function declaration |
| **Convert to zero parameter function** | Cursor on a read-only computed property |
| **Add documentation** | Cursor on a function, type, property, or macro declaration |

### Async/Await

| Action | Trigger |
|--------|---------|
| **Convert Call to Async Alternative** | Cursor on a call to a function with a completion handler |
| **Convert Function to Async** | Cursor on base name of a function not marked as `async` |
| **Add Async Alternative** | Cursor on base name of a function with an escaping completion handler parameter |
| **Add Async Wrapper** | Cursor on base name of a function with an escaping completion handler parameter |

### Types and Protocols

| Action | Trigger |
|--------|---------|
| **Add Missing Protocol Requirements** | Cursor on a type name that has unsatisfied protocol requirements |
| **Generate Memberwise Initializer** | Cursor on a type name that has stored properties |
| **Add Equatable Conformance** | Cursor on a type name that has stored properties and does not conform to `Equatable` |
| **Add Explicit Codable Implementation** | Cursor on a type name with `Codable` conformance |
| **Move To Extension** | Select one or more member declarations inside a type which aren't stored properties |
| **Convert To Computed Property** | Select a variable declaration with an initializer |
| **Expand 'some' parameters to generic parameters** | Cursor on a function declaration using `some` opaque parameter types |

### Source Organization

| Action | Trigger |
|--------|---------|
| **Remove Unused Imports** | Cursor on an import declaration (only available when file has no errors) |

### Package.swift Manifest Editing

| Action | Trigger |
|--------|---------|
| **Add library target** | Cursor anywhere in the call to the `Package` initializer |
| **Add executable target** | Cursor anywhere in the call to the `Package` initializer |
| **Add macro target** | Cursor anywhere in the call to the `Package` initializer |
| **Add test target (Swift Testing)** | Cursor on a `.target()`, `.executableTarget()`, or `.macro()` call |
| **Add test target (XCTest)** | Cursor on a `.target()`, `.executableTarget()`, or `.macro()` call |
| **Add product to export this target** | Cursor on a `.target()` or `.executableTarget()` call |

## Quick Fixes

Beyond refactorings, SourceKit-LSP also provides quick fixes for diagnostics.

Quick fixes appear alongside refactorings in the code actions menu but have the `quickfix` kind rather than `refactor`.

## Editor Support

Most LSP-compatible editors filter code actions by kind. Make sure your editor requests both `refactor` and `quickfix` kinds to see all available actions.

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
