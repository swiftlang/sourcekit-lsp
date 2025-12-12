# Contributing

This document contains notes about development and testing of SourceKit-LSP, the [Contributor Documentation](Contributor%20Documentation/) folder has some more detailed documentation.

## Building & Testing

SourceKit-LSP is a SwiftPM package, so you can build and test it using anything that supports packages - opening in Xcode, Visual Studio Code with [Swift for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode) installed, or through the command line using `swift build` and `swift test`. See below for extra instructions for Linux and Windows

SourceKit-LSP builds with the latest released Swift version and all its tests pass or, if unsupported by the latest Swift version, are skipped. Using the `main` development branch of SourceKit-LSP with an older Swift versions is not supported.

> [!TIP]
> SourceKit-LSP’s logging is usually very useful to debug test failures. On macOS these logs are written to the system log by default. To redirect them to stderr, build SourceKit-LSP with the `SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER` environment variable set to `1`:
> - In VS Code: Add the following to your `settings.json`:
>   ```json
>   "swift.swiftEnvironmentVariables": { "SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER": "1" },
>   ```
> - In Xcode
>   1. Product -> Scheme -> Edit Scheme…
>   2. Select the Arguments tab in the Run section
>   3. Add a `SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER` environment variable with value `1`
> - On the command line: Set the `SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER` environment variable to `1` when running tests, e.g by running `SOURCEKIT_LSP_FORCE_NON_DARWIN_LOGGER=1 swift test --parallel`

> [!TIP]
> Other useful environment variables during test execution are:
> - `SKIP_LONG_TESTS`: Skips tests that usually take longer than 1 second to execute. This significantly speeds up test time, especially with `swift test --parallel`
> - `SOURCEKIT_LSP_KEEP_TEST_SCRATCH_DIR`: Does not delete the temporary files created during test execution. Allows inspection of the test projects after the test finishes.

### Linux

The following dependencies of SourceKit-LSP need to be installed on your system
- libsqlite3-dev libncurses5-dev python3

You need to add `<path_to_swift_toolchain>/usr/lib/swift` and `<path_to_swift_toolchain>/usr/lib/swift/Block` C++ search paths to your `swift build` invocation that SourceKit-LSP’s dependencies build correctly. Assuming that your Swift toolchain is installed to `/`, the build command is

```sh
$ swift build -Xcxx -I/usr/lib/swift -Xcxx -I/usr/lib/swift/Block
```

### Windows

Make sure before building that your Windows machine or VM:
- Has [enabled developer mode](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode#enable-developer-mode)
- Git symlinks are enabled `git config --global --add core.symlinks true`  (May need to re-checkout after this)

To build SourceKit-LSP on Windows, the swift-syntax libraries need to be built as dynamic libraries so we do not exceed the maximum symbol limit in a single binary. Additionally, the equivalent search paths to the linux build need to be passed. Run the following in PowerShell.

```ps
> $env:SWIFTSYNTAX_BUILD_DYNAMIC_LIBRARY = 1; swift test  -Xcc -I -Xcc $env:SDKROOT\usr\include -Xcc -I -Xcc $env:SDKROOT\usr\include\Block
```

To work on SourceKit-LSP in VS Code, add the following to your `settings.json`, for other editors ensure that the `SWIFTSYNTAX_BUILD_DYNAMIC_LIBRARY` environment variable is set when launching `sourcekit-lsp`.

```json
"swift.swiftEnvironmentVariables": {
  "SWIFTSYNTAX_BUILD_DYNAMIC_LIBRARY": "1"
},
```

### Devcontainer

You can develop SourceKit-LSP inside a devcontainer, which is essentially a Linux container that has all of SourceKit-LSP’s dependencies pre-installed. The [official tutorial](https://code.visualstudio.com/docs/devcontainers/tutorial) contains information of how to set up devcontainers in VS Code.

Recommended Docker settings for macOS are:
- General
  - "Choose file sharing implementation for your containers": VirtioFS (better IO performance)
- Resources
  - CPUs: Allow docker to use most or all of your CPUs
  - Memory: Allow docker to use most or all of your memory

## Using a locally-built sourcekit-lsp in an editor

If you want test your changes to SourceKit-LSP inside your editor, you can point it to your locally-built `sourcekit-lsp` executable. The exact steps vary by editor. For VS Code, you can add the following to your `settings.json`.

```json
"swift.sourcekit-lsp.serverPath": "/path/to/sourcekit-lsp/.build/arm64-apple-macosx/debug/sourcekit-lsp",
```

> [!NOTE]
> VS Code will note that that the `swift.sourcekit-lsp.serverPath` setting is deprecated. That’s because mixing and matching versions of sourcekit-lsp and Swift toolchains is generally not supported, so the settings is reserved for developers of SourceKit-LSP, which includes you. You can ignore this warning, If you have the `swift.path` setting to a recent [Swift Development Snapshot](https://www.swift.org/install).

> [!TIP]
> The easiest way to debug SourceKit-LSP is usually to write a test case that reproduces the behavior and then debug that. If that’s not possible, you can attach LLDB to the sourcekit-lsp launched by your and set breakpoints to debug. To do so on the command line, run
> ```bash
> $ lldb --wait-for --attach-name sourcekit-lsp
> ```
>
> If you are developing SourceKit-LSP in Xcode, go to Debug -> Attach to Process by PID or Name.

## Selecting a Toolchain

When SourceKit-LSP is installed as part of a toolchain, it finds the Swift version to use relative to itself. When building SourceKit-LSP locally, it picks a default toolchain on your system, which usually corresponds to the toolchain that is used if you invoke `swift` without any specified path.

To adjust the toolchain that should be used by SourceKit-LSP (eg. because you want to use new `sourcekitd` features that are only available in a Swift open source toolchain snapshot but not your default toolchain), set the `SOURCEKIT_TOOLCHAIN_PATH` environment variable to your toolchain when running SourceKit-LSP.

## Logging

SourceKit-LSP has extensive logging to the system log on macOS and to `~/.sourcekit-lsp/logs/` or stderr on other platforms.

To show the logs on macOS, run
```sh
log show --last 1h --predicate 'subsystem CONTAINS "org.swift.sourcekit-lsp"' --info --debug
```
Or to stream the logs as they are produced:
```
log stream --predicate 'subsystem CONTAINS "org.swift.sourcekit-lsp"'  --level debug
```
On non-Apple platforms, you can use common commands like `tail` to read the logs or stream them as they are produced:
```
tail -F ~/.sourcekit-lsp/logs/*
```

SourceKit-LSP masks data that may contain private information such as source file names and contents by default. To enable logging of this information, follow the instructions in [Diagnose Bundle.md](Documentation/Diagnose%20Bundle.md).

## Formatting

SourceKit-LSP is formatted using [swift-format](http://github.com/swiftlang/swift-format) to ensure a consistent style.

To format your changes run the formatter using the following command
```bash
swift format -ipr .
```

If you are developing SourceKit-LSP in VS Code, you can also run the *Run swift-format* task from *Tasks: Run tasks* in the command palette.

## Generate configuration schema

If you modify the configuration options in [`SKOptions`](./Sources/SKOptions), you need to regenerate the configuration the JSON schema and the documentation by running the following command:

```bash
./sourcekit-lsp-dev-utils generate-config-schema
```

## Authoring commits

Prefer to squash the commits of your PR (*pull request*) and avoid adding commits like “Address review comments”. This creates a clearer git history, which doesn’t need to record the history of how the PR evolved.

We prefer to not squash commits when merging a PR because, especially for larger PRs, it sometimes makes sense to split the PR into multiple self-contained chunks of changes. For example, a PR might do a refactoring first before adding a new feature or fixing a bug. This separation is useful for two reasons:
- During review, the commits can be reviewed individually, making each review chunk smaller
- In case this PR introduced a bug that is identified later, it is possible to check if it resulted from the refactoring or the actual change, thereby making it easier find the lines that introduce the issue.

## Opening a PR

To submit a PR you don't need permissions on this repo, instead you can fork the repo and create a PR through your forked version.

For more information and instructions, read the GitHub docs on [forking a repo](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo).

Once you've pushed your branch, you should see an option on this repository's page to create a PR from a branch in your fork.

> [!TIP]
> If you are stuck, it’s encouraged to submit a PR that describes the issue you’re having, e.g. if there are tests that are failing, build failures you can’t resolve, or if you have architectural questions. We’re happy to work with you to resolve those issues.

## Opening a PR for Release Branch

See the [dedicated section][section] on the Swift project website.

[section]: https://www.swift.org/contributing/#release-branch-pull-requests

## Review and CI Testing

After you opened your PR, a maintainer will review it and test your changes in CI (*Continuous Integration*) by adding a `@swift-ci Please test` comment on the pull request. Once your PR is approved and CI has passed, the maintainer will merge your pull request.

Only contributors with [commit access](https://www.swift.org/contributing/#commit-access) are able to approve pull requests and trigger CI.
