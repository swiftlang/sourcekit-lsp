# Environment variables

The following environment variables can be used to control some behavior in SourceKit-LSP

## Build time

- `SOURCEKITLSP_FORCE_NON_DARWIN_LOGGER`: Use the `NonDarwinLogger` to log to stderr, even when building SourceKit-LSP on macOS. This is useful when running tests using `swift test` because it writes the log messages to stderr, which is displayed during the `swift test` invocation.
- `SOURCEKIT_LSP_CI_INSTALL`: Modifies rpaths in a way that’s necessary to build SourceKit-LSP to be included in a distributed toolchain. Should not be used locally.
- `SWIFTCI_USE_LOCAL_DEPS`: Assume that all of SourceKit-LSP’s dependencies are checked out next to it and use those instead of cloning the repositories. Primarily intended for CI environments that check out related branches.

## Runtime

- `SOURCEKITLSP_LOG_LEVEL`: When using `NonDarwinLogger`, specify the level at which messages should be logged. Defaults to `debug` in debug build and `default` in release builds. Primarily used to increase the log level when running tests from a release build in Swift CI. To adjust the logging on user devices, use the [Configuration file](Configuration%20File.md).
- `SOURCEKITLSP_LOG_PRIVACY_LEVEL`: When using `NonDarwinLogger`, specifies whether information that might contain sensitive information (essentially source code) should be logged. Defaults to `private` in debug build and `public` in release builds. Primarily used to log sensitive information when running tests from a release build in Swift CI. To adjust the logging on user devices, use the [Configuration file](Configuration%20File.md).

## Testing
- `SKIP_LONG_TESTS`: Skip tests that typically take more than 1s to execute.
- `SOURCEKITLSP_KEEP_TEST_SCRATCH_DIR`: Does not delete the temporary files created during test execution. Allows inspection of the test projects after the test finishes.
- `SOURCEKIT_LSP_TEST_MODULE_CACHE`: Specifies where tests should store their shared module cache. Defaults to writing the module cache to a temporary directory. Intended so that CI systems can clean the module cache directory after running.
