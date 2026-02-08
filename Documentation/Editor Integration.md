# Editor Integration

Most modern text editors support the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) (LSP) and many have support for Swift through SourceKit-LSP. https://www.swift.org/tools has a list of some popular editors and how to set them up. This page covers any editors not listed there.

<!-- Editors are sorted alphabetically followed by the generic other editor section -->
<!-- All editors included in this list should offer at least basic functionality free of charge -->

## BBEdit

Support for LSP is built in to BBEdit 14.0 and later.

If `sourcekit-lsp` is in your `$PATH` or is discoverable by using `xcrun --find sourcekit-lsp`, BBEdit will use it automatically. Otherwise you can manually configure BBEdit to use a suitable `sourcekit-lsp` as needed.

You can read more about BBEdit's LSP support and configuration hints [here](https://www.barebones.com/support/bbedit/lsp-notes.html).

## Nova

You can use SourceKit-LSP with Nova by using the [Icarus](http://panic.com/open-in-nova/extension?id=panic.Icarus) extension.

By default, Icarus will try to discover `sourcekit-lsp` automatically (using `xcrun --find sourcekit-lsp`), but can be configured to look at an installed Swift toolchain package (using `xcrun --toolchain swift --find sourcekit-lsp`) or custom path. To do so, open the extension settings from Nova's Extensions menu: Extension Library… -> Icarus -> Settings -> Toolchain.

The Icarus source is located within [its repository](https://github.com/panicinc/icarus).

## Sublime Text

Before using SourceKit-LSP with Sublime Text, you will need to install the [LSP](https://packagecontrol.io/packages/LSP), [LSP-SourceKit](https://github.com/sublimelsp/LSP-SourceKit) and [Swift-Next](https://github.com/Swift-Next/Swift-Next) packages from Package Control. Then toggle the server on by typing in command palette `LSP: Enable Language Server Globally` or `LSP: Enable Language Server in Project`.

## Theia Cloud IDE

You can use SourceKit-LSP with Theia by using the `theiaide/theia-swift` image. To use the image you need to have [Docker](https://docs.docker.com/get-started/) installed first.

The following command pulls the image and runs Theia IDE on http://localhost:3000 with the current directory as a workspace.

```bash
$ docker run -it -p 3000:3000 -v "$(pwd):/home/project:cached" theiaide/theia-swift:next
```

You can pass additional arguments to Theia after the image name, for example to enable debugging:

```bash
$ docker run -it -p 3000:3000 --expose 9229 -p 9229:9229 -v "$(pwd):/home/project:cached" theiaide/theia-swift:next --inspect=0.0.0.0:9229
```

Image Variants
- `theiaide/theia-swift:latest`: This image is based on the latest stable released version.
- `theiaide/theia-swift:next`: This image is based on the nightly published version.

The `theia-swift-docker` source is located at [theia-apps](https://github.com/theia-ide/theia-apps).

## Other Editors

SourceKit-LSP should work with any editor that supports the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) (LSP). Each editor has its own mechanism for configuring an LSP server, so consult your editor's documentation for the specifics. In general, you can configure your editor to use SourceKit-LSP for Swift, C, C++, Objective-C and Objective-C++ files; the editor will need to be configured to find the `sourcekit-lsp` executable from your installed Swift toolchain, which expects to communicate with the editor over `stdin` and `stdout`.

## Building a new SourceKit-LSP Client

If you are building a new SourceKit-LSP client for an editor, here are some critical hints that may help you. Some of these are general hints for development of an LSP client.

- SourceKit-LSP has extensive logging. See the [Logging section in CONTRIBUTING.md](../CONTRIBUTING.md#logging) for more information.
- You have to [open a document](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_didOpen) before sending document-based requests.
- [Don't](https://forums.swift.org/t/how-do-you-build-a-sandboxed-editor-that-uses-sourcekit-lsp/40906) attempt to use Sourcekit-LSP in [a sandboxed context](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox):
    - As with most developer tooling, SourceKit-LSP relies on other system- and language tools that it would not be allowed to access from within an app sandbox.
- Strictly adhere to the format specification of LSP packets, including their [header- and content part](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#headerPart).
- Piece LSP packets together from the stdout data:
  - SourceKit-LSP outputs LSP packets to stdout, but: Single chunks of data output do not correspond to single packets. stdout rather delivers a stream of data. You have to buffer that stream in some form and detect individual LSP packets in it.
- Provide the current system environment variables to SourceKit-LSP:
  - SourceKit-LSP must read some current environment variables of the system, so [don't wipe them all out](https://forums.swift.org/t/making-a-sourcekit-lsp-client-find-references-fails-solved/57426) when providing modified or additional variables.
