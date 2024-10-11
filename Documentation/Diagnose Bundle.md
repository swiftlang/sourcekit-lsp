# Diagnose Bundle

A diagnose bundle is designed to help SourceKit-LSP developers diagnose and fix reported issues.
You can generate a diagnose bundle with:
```sh
sourcekit-lsp diagnose
```

And then attach the resulting `sourcekit-lsp-diagnose-*` bundle to any bug reports.

You may want to inspect the bundle to determine whether you're willing to share the collected information. At a high level they contain:
- Crash logs from SourceKit
  - From Xcode toolchains, just a stack trace.
  - For assert compilers (ie. nightly toolchains) also sometimes some source code that was currently compiled to cause the crash.
- Log messages emitted by SourceKit
  - We mark all information that may contain private information (source code, file names, …) as private by default, so all of that will be redacted. Private logging can be enabled for SourceKit-LSP as described in [Enable Extended Logging](#enable-extended-logging). On macOS these extended log messages are also included in a sysdiagnose.
- Versions of Swift installed on your system
- If possible, a minimized project that caused SourceKit to crash
- If possible, a minimized project that caused the Swift compiler to crash

## Enable Extended logging

Extended logging of SourceKit-LSP is not enabled by default because it contains information about your source code, directory structure, and similar potentially sensitive information. Instead, the logging system redacts that information. If you are comfortable with sharing such information, you can enable extended SourceKit-LSP’s extended logging, which improves the ability of SourceKit-LSP developers to understand and fix issues.

### macOS

To enable extended logging on macOS, install the configuration profile from https://github.com/swiftlang/sourcekit-lsp/blob/main/Documentation/Enable%20Extended%20Logging.mobileconfig as described in https://support.apple.com/guide/mac-help/configuration-profiles-standardize-settings-mh35561/mac#mchlp41bd550. SourceKit-LSP will immediately stop redacting information and include them in the system log.

To disable extended logging again, remove the configuration profile as described in https://support.apple.com/guide/mac-help/configuration-profiles-standardize-settings-mh35561/mac#mchlpa04df41.

### Non-Apple platforms

To enable extended logging on non-Apple platforms, create a [configuration file](Configuration%20File.md) with the following contents at `~/.sourcekit-lsp/config.json` with the following contents:
```json
{
  "logging": {
    "level": "debug",
    "privacyLevel": "private"
  }
}
```
