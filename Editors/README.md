# Editor Integration

This document contains information about how to configure an editor to use SourceKit-LSP. If your editor is not listed below, but it supports the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) (LSP), see [Other Editors](#other-editors).

In general, you will need to know where to find the `sourcekit-lsp` server exectuable. Some examples:

* With Xcode 11.4+
  * `xcrun sourcekit-lsp` - run the server
  * `xcrun --find sourcekit-lsp` - get the full path to the server
* Toolchain from Swift.org
  * Linux
    * You will find `sourcekit-lsp` in the `bin` directory of the toolchain.
  * macOS
    * `xcrun --toolchain swift sourcekit-lsp` - run the server
    * `xcrun --toolchain swift --find sourcekit-lsp` - get the full path to the server
* Built from source
  * `.build/<platform>/<configuration>/sourcekit-lsp`

## Visual Studio Code

To use SourceKit-LSP with Visual Studio Code, you will need the [SourceKit-LSP
Visual Studio Code extension](vscode). Documentation for [Building and Installing](vscode/README.md#building-and-installing-the-extension) is in the extension's README. There is also information about [Configuration](vscode/README.md#configuration). The most common settings are listed below.

After installing the extension, settings for SourceKit-LSP can be found in `Preferences > Settings` under
`Extensions > SourceKit-LSP` or by searching for the setting prefix
`sourcekit-lsp.`.

* `sourcekit-lsp.serverPath`: The path to sourcekit-lsp executable
* `sourcekit-lsp.toolchainPath`: (optional) The path of the swift toolchain (sets `SOURCEKIT_TOOLCHAIN_PATH`). By default, sourcekit-lsp uses the toolchain it is installed in.
* `sourcekit-lsp.tracing.server`: Traces the communication between VS Code and the SourceKit-LSP language server

## Atom

Download the `ide-sourcekit` package for Atom from [the corresponding package page](https://atom.io/packages/ide-sourcekit). It also contains installation instructions to get you started.

## Sublime Text

Before using SourceKit-LSP with Sublime Text, you will need to install the LSP package from Package Control. To configure SourceKit-LSP, open the LSP package's settings. The following snippet should be enough to get started with Swift.

You will need the path to the `sourcekit-lsp` executable for the "command" section.

```json
{
  "clients":
  {
    "SourceKit-LSP":
    {
      "enabled": true,
      "command": [
        "<sourcekit-lsp command>"
      ],
      "env": {
        // To override the toolchain, uncomment the following:
        // "SOURCEKIT_TOOLCHAIN_PATH": "<path to toolchain>",
      },
      "languages": [
        {
          "scopes": ["source.swift"],
          "syntaxes": [
            "Packages/Swift/Syntaxes/Swift.tmLanguage",
            "Packages/Decent Swift Syntax/Swift.sublime-syntax",
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

## Vim 8 or Neovim

All methods below assume `sourcekit-lsp` is in your `PATH`. If it's not then replace `sourcekit-lsp` with the absolute path to the sourcekit-lsp executable.

### vim-lsp

Install [vim-lsp](https://github.com/prabirshrestha/vim-lsp). In your `.vimrc`, configure vim-lsp to use sourcekit-lsp for Swift source files like so:

```viml
if executable('sourcekit-lsp')
    au User lsp_setup call lsp#register_server({
        \ 'name': 'sourcekit-lsp',
        \ 'cmd': {server_info->['sourcekit-lsp']},
        \ 'whitelist': ['swift'],
        \ })
endif
```

In order for vim to recognize Swift files, you need to configure the filetype. Otherwise, `:LspStatus` will show that sourcekit-lsp is not running even if a Swift file is open.

If you are already using a Swift plugin for vim, like [swift.vim](https://github.com/keith/swift.vim), this may be setup already. Otherwise, you can set the filetype manually:

```viml
augroup filetype
  au! BufRead,BufNewFile *.swift set ft=swift
augroup END
```

That's it! As a test, open a swift file, put cursor on top of a symbol in normal mode and
run `:LspDefinition`. More commands are documented [here](https://github.com/prabirshrestha/vim-lsp#supported-commands).

There are many Vim solutions for code completion. For instance, you may want to use LSP for omnifunc:

```viml
autocmd FileType swift setlocal omnifunc=lsp#complete
```

With this added in `.vimrc`, you can use `<c-x><c-o>` in insert mode to trigger sourcekit-lsp completion.

### coc.nvim

With [coc.nvim installed](https://github.com/neoclide/coc.nvim#quick-start), the easiest is to use the [coc-sourcekit](https://github.com/klaaspieter/coc-sourcekit) plugin:

```vim
:CocInstall coc-sourcekit
```

Alternatively open your coc config (`:CocConfig` in vim) and add:

```json
  "languageserver": {
    "sourcekit-lsp": {
      "filetypes": ["swift"],
      "command": "sourcekit-lsp",
    }
  }
```

As a test, open a Swift file, put the cursor on top of a symbol in normal mode and run:

```
:call CocAction('jumpDefinition')
```

## Theia Cloud IDE

You can use SourceKit-LSP with Theia by using the `theiaide/theia-swift` image. To use the image you need to have [Docker](https://docs.docker.com/get-started/) installed first.

The following command pulls the image and runs Theia IDE on http://localhost:3000 with the current directory as a workspace.

    docker run -it -p 3000:3000 -v "$(pwd):/home/project:cached" theiaide/theia-swift:next

You can pass additional arguments to Theia after the image name, for example to enable debugging:

    docker run -it -p 3000:3000 --expose 9229 -p 9229:9229 -v "$(pwd):/home/project:cached" theiaide/theia-swift:next --inspect=0.0.0.0:9229

Image Variants

`theiaide/theia-swift:latest`
This image is based on the latest stable released version.

`theiaide/theia-swift:next`
This image is based on the nightly published version.

theia-swift-docker source [theia-apps](https://github.com/theia-ide/theia-apps)


## Other Editors

SourceKit-LSP should work with any editor that supports the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
(LSP). Each editor has its own mechanism for configuring an LSP server, so consult your editor's
documentation for the specifics. In general, you can configure your editor to use SourceKit-LSP for
Swift, C, C++, Objective-C and Objective-C++ files; the editor will need to be configured to find
the `sourcekit-lsp` executable (see the top-level [README](https://github.com/apple/sourcekit-lsp) for build instructions), which
expects to communicate with the editor over `stdin` and `stdout`.
