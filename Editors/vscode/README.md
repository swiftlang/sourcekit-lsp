# SourceKit-LSP for Visual Studio Code

This extension adds support to Visual Studio Code for using SourceKit-LSP, a
language server for Swift and C/C++/Objective-C languages.

**Note**: SourceKit-LSP is under heavy development and this should be considered
a preview. Users will need to separately provide the `sourcekit-lsp` executable
as well as a Swift toolchain.

## Building and Installing the Extension

Currently, the way to get the extension is to build and install it from source.
You will also need the `sourcekit-lsp` language server executable and a Swift
toolchain. For more information about sourcekit-lsp, see [here](https://github.com/apple/sourcekit-lsp).

**Prerequisite**: To build the extension, you will need Node.js and npm: https://www.npmjs.com/get-npm.

The following commands build the extension and creates a `.vsix` package in the `out` directory.

```
$ cd Editors/vscode
$ npm run createDevPackage
```

You can install the package from the command-line using the `code` command if available (see [Launching from the command line](https://code.visualstudio.com/docs/setup/mac#_launching-from-the-command-line)).

```
code --install-extension out/sourcekit-lsp-vscode-dev.vsix
```

Or you can install from within the application using the `Extensions > Install from VSIX...` command from the command palette.

### Developing the Extension in Visual Studio Code

As an alternative, you can open the extension directory from Visual Studio Code and build it from within the application.

1. Run `npm install` inside the extension directory to install dependencies.
2. Open the extension directory in Visual Studio Code.
3. Hit `F5` to build the extension and launch an editor window that uses it.

This will start debugging a special instance of Visual Studio Code that will have "[Extension Development Host]" in the window title and use the new extension.

There is extensive documentation for developing extensions from within Visual Studio Code at https://code.visualstudio.com/docs/extensions/overview.

## Configuration

Settings for SourceKit-LSP can be found in `Preferences > Settings` under
`Extensions > SourceKit-LSP` or by searching for the setting prefix
`sourcekit-lsp.`.

* Server Path: The path of the sourcekit-lsp executable
* Toolchain Path: The path of the swift toolchain (sets `SOURCEKIT_TOOLCHAIN_PATH`)

The extension will find the `sourcekit-lsp` executable automatically if it is in
`PATH`, or it can be provided manually using this setting.
