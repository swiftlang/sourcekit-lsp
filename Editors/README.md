# Editor Integration

This document contains information about how to configure an editor to use SourceKit-LSP. If your editor is not listed below, but it supports the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) (LSP), see [Other Editors](#other-editors).

## Visual Studio Code

To use SourceKit-LSP with Visual Studio Code, you will need the [SourceKit-LSP
Visual Studio Code extension](vscode). Documentation for [Building and Installing](vscode/README.md#building-and-installing-the-extension) is in the extension's README. There is also information about [Configuration](vscode/README.md#configuration). The most common settings are listed below.

After installing the extension, settings for SourceKit-LSP can be found in `Preferences > Settings` under
`Extensions > SourceKit-LSP` or by searching for the setting prefix
`sourcekit-lsp.`.

* `sourcekit-lsp.serverPath`: The path to sourcekit-lsp executable
* `sourcekit-lsp.toolchainPath`: The path to the swift toolchain (sets `SOURCEKIT_TOOLCHAIN_PATH`)
* `sourcekit-lsp.tracing.server`: Traces the communication between VS Code and the SourceKit-LSP language server

## Sublime Text

Before using SourceKit-LSP with Sublime Text, you will need to install the LSP package from Package Control. To configure SourceKit-LSP, open the LSP package's settings. The following snippet should be enough to get started with Swift.

You will need the path to the `sourcekit-lsp` executable and the Swift toolchain for the "command" and "env" sections.

```json
{
  "clients":
  {
    "SourceKit-LSP":
    {
      "enabled": true,
      "command": [
        "<path to sourcekit-lsp>"
      ],
      "env": {
        "SOURCEKIT_TOOLCHAIN_PATH": "<path to toolchain>",
      },
      "languages": [
        {
          "scopes": ["source.swift"],
          "syntaxes": [
            "Packages/Swift/Syntaxes/Swift.tmLanguage",
          ],
          "languageId": "swift"
        },
        {
          "scopes": ["source.c"],
          "syntaxes": ["Packages/C++/C.sublime-syntax"],
          "languageId": "c"
        },
        {
          "scopes": ["source.c++"],
          "syntaxes": ["Packages/C++/C++.sublime-syntax"],
          "languageId": "cpp"
        },
        {
          "scopes": ["source.objc"],
          "syntaxes": ["Packages/Objective-C/Objective-C.sublime-syntax"],
          "languageId": "objective-c"
        },
        {
          "scopes": ["source.objc++"],
          "syntaxes": ["Packages/Objective-C/Objective-C++.sublime-syntax"],
          "languageId": "objective-cpp"
        },
      ]
    }
  }
}
```

## Emacs

There is an Emacs client for SourceKit-LSP in the [main Emacs LSP repository](https://github.com/emacs-lsp/lsp-sourcekit).

## Vim 8

Install [vim-lsp](https://github.com/prabirshrestha/vim-lsp). In your `.vimrc`, configure vim-lsp to use
sourcekit-lsp for Swift source files like so:

```
if executable('sourcekit-lsp')
    au User lsp_setup call lsp#register_server({
        \ 'name': 'sourcekit-lsp',
        \ 'cmd': {server_info->['sourcekit-lsp']},
        \ 'whitelist': ['swift'],
        \ })
endif
```

(…assuming `sourckit-lsp` is in your PATH variable, otherwise replace `'sourcekit-lsp'` with path to your
command location).

That's it! As a test, open a source file in an Xcode project, put cursor on top of a symbol in normal mode and
run `:LspDefinition`. More commands is documented [here](https://github.com/prabirshrestha/vim-lsp#supported-commands).

There are many Vim solutions for autocomplete. For instance, you may want to use LSP for omnifunc:

```
autocmd FileType swift setlocal omnifunc=lsp#complete
```

With this added in `.vimrc`, you can use `<c-x><c-o>` in insert mode to trigger sourcekit-lsp autocompletion.

## Other Editors

SourceKit-LSP should work with any editor that supports the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
(LSP). Each editor has its own mechanism for configuring an LSP server, so consult your editor's
documentation for the specifics. In general, you can configure your editor to use SourceKit-LSP for
Swift, C, C++, Objective-C and Objective-C++ files; the editor will need to be configured to find
the `sourcekit-lsp` executable (see the top-level [README](https://github.com/apple/sourcekit-lsp) for build instructions), which
expects to communicate with the editor over `stdin` and `stdout`.
