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
  - We mark all information that may contain private information (source code, file names, …) as private by default, so all of that will be redacted. Private logging can be enabled for SourceKit-LSP as described in [Enable Extended Logging](Enable%20Extended%20Logging.md). On macOS these extended log messages are also included in a sysdiagnose.
- Versions of Swift installed on your system
- If possible, a minimized project that caused SourceKit to crash
- If possible, a minimized project that caused the Swift compiler to crash
