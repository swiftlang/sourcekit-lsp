# Code Actions

SourceKit-LSP is selective about accepting new code actions.

Code actions appear directly in editor UI, so adding too many can create noise. In general, a proposed code action should ideally satisfy all of the following:

- **Hard to get right** - the change is non-trivial and easy to implement incorrectly by hand.
- **Common** - the situation occurs frequently enough to justify dedicated tooling.
- **Tedious** - performing the change manually would require repetitive or mechanical edits.
- **Not already covered by other tools** - the functionality should not duplicate what is more appropriately provided by other tools such as linters or formatters.

Code actions that do not meet these criteria are unlikely to be accepted.

## Proposing a new code action

Before implementing a new code action, contributors should first file a GitHub issue describing the proposal and wait for guidance from the code owners.

## Implementation location

Code actions should generally be implemented in [**sourcekit-lsp**](https://github.com/swiftlang/sourcekit-lsp/tree/main/Sources/SwiftLanguageService/CodeActions), since they are primarily a language-server feature.

They should only be implemented in [**swift-syntax**](https://github.com/swiftlang/swift-syntax/tree/main/Sources/SwiftRefactor) when there is a clear reason to do so, such as when the functionality needs to be reused outside of the language server.
