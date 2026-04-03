# Using a Local Build of SourceKit

This guide explains how to run SourceKit-LSP against a local build of SourceKit from the Swift monorepo.

Examples in this document use the checkout layout from Swift's [How to Set Up an Edit-Build-Test-Debug Loop](https://github.com/swiftlang/swift/blob/main/docs/HowToGuides/GettingStarted.md), ie.`swift-project/swift` and `swift-project/sourcekit-lsp` as sibling directories.
This layout is only for convenience.
`sourcekit-lsp` and `swift` can live in different directories as long as you pass the correct absolute paths.

## 1. Build Swift

Follow the [How to Set Up an Edit-Build-Test-Debug Loop](https://github.com/swiftlang/swift/blob/main/docs/HowToGuides/GettingStarted.md) guide to clone Swift and get the required dependencies. Then, add the following additional flags to the `build-script` invocation: `--swift-testing`, `--swift-testing-macros`, `--llbuild`, `--swiftpm` and `--install-all`.
These flags are necessary to build the components of Swift that SourceKit-LSP depends on, and to ensure that a toolchain with all the necessary components is created.
When using the `build-script` command from the guide the entire command becomes:

- macOS:

  ```sh
  utils/build-script --skip-build-benchmarks \
    --swift-darwin-supported-archs "$(uname -m)" \
    --release-debuginfo --swift-disable-dead-stripping \
    --bootstrapping=hosttools \
    --swift-testing \
    --swift-testing-macros \
    --llbuild \
    --swiftpm \
    --install-all
  ```

- Linux:

  ```sh
  utils/build-script --release-debuginfo \
    --swift-testing \
    --swift-testing-macros \
    --llbuild \
    --swiftpm \
    --install-all
  ```

## 2. Point SourceKit-LSP to that toolchain

Set the `SOURCEKIT_TOOLCHAIN_PATH` environment variable when running
tests or launching SourceKit-LSP to point to the `.xctoolchain` directory of the locally built toolchain.
The path should look something like this: `.../swift-project/build/Ninja-RelWithDebInfoAssert/toolchain-macosx-arm64/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain`.
You may need to adjust the path based on the build configuration and platform.

Example (assuming `sourcekit-lsp` and `swift` are sibling directories):

```bash
SOURCEKIT_TOOLCHAIN_PATH="$PWD/../build/Ninja-RelWithDebInfoAssert/toolchain-macosx-arm64/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain" \
swift test
```

(you may need to adjust the path based on the build configuration and platform)

## 3. Making Changes to SourceKit

When making changes to SourceKit, you can iterate faster by only rebuilding SourceKit and its dependencies instead of rebuilding the entire Swift toolchain.
You need to ensure that the toolchain gets updated with the new build artifacts.
This can be done by running the following command from the `build/Ninja-RelWithDebInfoAssert/swift-macosx-arm64` directory after building Swift with the `build-script` command from step 1:

```bash
DESTDIR=../toolchain-macosx-arm64 ninja sourcekitd sourcekit-inproc install-sourcekit-xpc-service install-sourcekit-inproc
```

(you may need to adjust the path based on the build configuration and platform)

## SourceKit modes on macOS

Normally, SourceKit-LSP uses XPC on macOS to communicate with SourceKit, while on Linux SourceKit runs in the same process as SourceKit-LSP.
However, sometimes it may be desirable to run SourceKit in-process on macOS as well.
Running SourceKit in-process can be useful when using the `SOURCEKIT_LOGGING` environment variable, as the output will include the log messages from SourceKit itself instead of just the messages from the SourceKit wrapper in SourceKit-LSP.

To force SourceKit-LSP to run SourceKit in process, set the `SOURCEKIT_LSP_RUN_SOURCEKITD_IN_PROCESS` environment variable.

```bash
SOURCEKIT_LSP_RUN_SOURCEKITD_IN_PROCESS=1 swift test
```
