# Build a SourceKit-LSP Client

Here are some critical hints that may help developers of editors or language plugins in adopting SourceKit-LSP: 

* Remember that SourceKit-LSP is at an early stage:
    * It is [not yet](https://forums.swift.org/t/what-does-sourcekit-lsp-support/54424) a complete or necessarily accurate reflection of the LSP.
    * Logs from `stdErr` may be insufficient for debugging your interaction with `sourcekit-lsp`.
    * [Currently](https://github.com/apple/sourcekit-lsp/issues/529), you have to [open a document](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didOpen) before sending document-based requests.
* You can use `sourcekit-lsp` with Swift packages but [not (yet) with Xcode projects](https://forums.swift.org/t/xcode-project-support/20927). 
* [Don't](https://forums.swift.org/t/how-do-you-build-a-sandboxed-editor-that-uses-sourcekit-lsp/40906) attempt to use `sourcekit-lsp` in [a sandboxed context](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox):
    * As with most developer tooling, `sourcekit-lsp` relies on other system- and language tools that it would not be allowed to access from within an app sandbox.
* Strictly adhere to the format specification of LSP packets, including their [header- and content part](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#headerPart).
* Piece LSP packets together from the `stdOut` data:
    * `sourcekit-lsp` outputs LSP packets to `stdOut`, but: Single chunks of data output do not correspond to single packets. `stdOut` rather delivers a stream of data. You have to buffer that stream in some form and detect individual LSP packets in it.
* Provide the current system environment variables to `sourcekit-lsp`:
    * `sourcekit-lsp` must read some current environment variables of the system, so [don't wipe them all out](https://forums.swift.org/t/making-a-sourcekit-lsp-client-find-references-fails-solved/57426) when providing modified or additional variables.
