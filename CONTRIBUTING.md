# Contributing

This document contains notes about development and testing of SourceKit-LSP.

## Building & Testing

SourceKit-LSP is a SwiftPM package, so you can build and test it using anything that supports packages - opening in Xcode, Visual Studio Code with [Swift for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=sswg.swift-lang) installed, or through the command line using `swift build` and `swift test`. See below for extra instructions for Linux and Windows

SourceKit-LSP builds with the latest released Swift version and all its tests pass or, if unsupported by the latest Swift version, are skipped. Using the `main` development branch of SourceKit-LSP with an older Swift versions is not supported.

> [!TIP]
> SourceKit-LSP’s logging is usually very useful to debug test failures. On macOS these logs are written to the system log by default. To redirect them to stderr, build SourceKit-LSP with the `SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER` environment variable set to `1`:
> - In VS Code: Add the following to your `settings.json`:
>   ```json
>   "swift.swiftEnvironmentVariables": { "SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER": "1" },
>   ```
> - In Xcode
>   1. Product -> Scheme -> Edit Scheme…
>   2. Select the Arguments tab in the Run section
>   3. Add a `SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER` environment variable with value `1`
> - On the command line: Set the `SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER` environment variable to `1` when running tests, e.g by running `SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER=1 swift test --parallel`

> [!TIP]
> Other useful environment variables during test execution are:
> - `SKIP_LONG_TESTS`: Skips tests that usually take longer than 1 second to execute. This significantly speeds up test time, especially with `swift test --parallel`
> - `SOURCEKITLSP_KEEP_TEST_SCRATCH_DIR`: Does not delete the temporary files created during test execution. Allows inspection of the test projects after the test finishes.

### Linux

The following dependencies of SourceKit-LSP need to be installed on your system
- libsqlite3-dev libncurses5-dev python3

You need to add `<path_to_swift_toolchain>/usr/lib/swift` and `<path_to_swift_toolchain>/usr/lib/swift/Block` C++ search paths to your `swift build` invocation that SourceKit-LSP’s dependencies build correctly. Assuming that your Swift toolchain is installed to `/`, the build command is

```sh
$ swift build -Xcxx -I/usr/lib/swift -Xcxx -I/usr/lib/swift/Block
```

### Windows

You must provide the following dependencies for SourceKit-LSP:
- SQLite3 ninja

```cmd
> swift build -Xcc -I<absolute path to SQLite header search path> -Xlinker -L<absolute path to SQLite library search path> -Xcc -I%SDKROOT%\usr\include -Xcc -I%SDKROOT%\usr\include\Block
```

The header and library search paths must be passed to the build by absolute path. This allows the clang importer and linker to find the dependencies.

Additionally, as SourceKit-LSP depends on libdispatch and the Blocks runtime, which are part of the SDK, but not in the default search path, need to be explicitly added.

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

SourceKit-LSP has extensive logging to the system log on macOS and to `/var/logs/sourcekit-lsp` or stderr on other platforms.

To show the logs on macOS, run
```sh
log show --last 1h --predicate 'subsystem CONTAINS "org.swift.sourcekit-lsp"' --info --debug
```
Or to stream the logs as they are produced:
```
log stream --predicate 'subsystem CONTAINS "org.swift.sourcekit-lsp"'  --level debug
```

SourceKit-LSP masks data that may contain private information such as source file names and contents by default. To enable logging of this information, run

```sh
sudo log config --subsystem org.swift.sourcekit-lsp --mode private_data:on
```

To enable more verbose logging on non-macOS platforms, launch sourcekit-lsp with the `SOURCEKITLSP_LOG_LEVEL` environment variable set to `debug`.


## Formatting

SourceKit-LSP is formatted using [swift-format](http://github.com/swiftlang/swift-format) to ensure a consistent style.

To format your changes run the formatter using the following command
```bash
swift package format-source-code
```

If you are developing SourceKit-LSP in VS Code, you can also run the *Run swift-format* task from *Tasks: Run tasks* in the command palette.

## Authoring commits

Prefer to squash the commits of your PR (*pull request*) and avoid adding commits like “Address review comments”. This creates a clearer git history, which doesn’t need to record the history of how the PR evolved.

We prefer to not squash commits when merging a PR because, especially for larger PRs, it sometimes makes sense to split the PR into multiple self-contained chunks of changes. For example, a PR might do a refactoring first before adding a new feature or fixing a bug. This separation is useful for two reasons:
- During review, the commits can be reviewed individually, making each review chunk smaller
- In case this PR introduced a bug that is identified later, it is possible to check if it resulted from the refactoring or the actual change, thereby making it easier find the lines that introduce the issue.

## Opening a PR

To submit a PR you don't need permissions on this repo, instead you can fork the repo and create a PR through your forked version.

For more information and instructions, read the GitHub docs on [forking a repo](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo).

Once you've pushed your branch, you should see an option on this repository's page to create a PR from a branch in your fork.

## Opening a PR for Release Branch

In order for a pull request to be considered for inclusion in a release branch (e.g. `release/6.0`) after it has been cut, it must meet the following requirements:

1. The title of the PR should start with the tag `[{swift version number}]`. For example, `[6.0]` for the Swift 6.0 release branch.

1. The PR description must include the following information:

    ```md
    * **Explanation**: A description of the issue being fixed or enhancement being made. This can be brief, but it should be clear.
    * **Scope**: An assessment of the impact/importance of the change. For example, is the change a source-breaking language change, etc.
    * **Issue**: The GitHub Issue link if the change fixes/implements an issue/enhancement.
    * **Original PR**: Pull Request link from the `main` branch.
    * **Risk**: What is the (specific) risk to the release for taking this change?
    * **Testing**: What specific testing has been done or needs to be done to further validate any impact of this change?
    * **Reviewer**: One or more code owners for the impacted components should review the change. Technical review can be delegated by a code owner or otherwise requested as deemed appropriate or useful.
    ```

> [!TIP]
> The PR description can be generated using the [release_branch.md](https://github.com/swiftlang/sourcekit-lsp/blob/main/.github/PULL_REQUEST_TEMPLATE/release_branch.md) [pull request template](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/about-issue-and-pull-request-templates). To use this template when creating a PR, you need to add the query parameter:
> ```
> ?expand=1&template=release_branch.md
> ```
> to the PR URL, as described in the [GitHub documentation on using query parameters to create a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/using-query-parameters-to-create-a-pull-request).
> This is necessary because GitHub does not currently provide a UI to choose a PR template.

All changes going into a release branch must go through pull requests that are approved and merged by the corresponding release manager.

## Review and CI Testing

After you opened your PR, a maintainer will review it and test your changes in CI (*Continuous Integration*) by adding a `@swift-ci Please test` comment on the pull request. Once your PR is approved and CI has passed, the maintainer will merge your pull request.

Only contributors with [commit access](https://www.swift.org/contributing/#commit-access) are able to approve pull requests and trigger CI.
