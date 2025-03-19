# Enable Extended logging

By default, SourceKit-LSP redacts information about your source code, directory structure, and similar potentially sensitive information from its logs. If you are comfortable with sharing such information, you can enable SourceKit-LSP’s extended logging, which improves the ability of SourceKit-LSP developers to understand and fix issues.

When extended logging is enabled, it will log extended information from that point onwards. To capture the extended logs for an issue you are seeing, please reproduce the issue after enabling extended logging and capture a diagnose bundle by running `sourcekit-lsp diagnose` in terminal.

## macOS

To enable extended logging on macOS, install the configuration profile from https://github.com/swiftlang/sourcekit-lsp/blob/main/Documentation/Enable%20Extended%20Logging.mobileconfig as described in https://support.apple.com/guide/mac-help/configuration-profiles-standardize-settings-mh35561/mac#mchlp41bd550. SourceKit-LSP will immediately stop redacting information and include them in the system log.

To disable extended logging again, remove the configuration profile as described in https://support.apple.com/guide/mac-help/configuration-profiles-standardize-settings-mh35561/mac#mchlpa04df41.

## Non-Apple platforms

To enable extended logging on non-Apple platforms, create a [configuration file](Configuration%20File.md) at `~/.sourcekit-lsp/config.json` with the following contents:
```json
{
  "logging": {
    "level": "debug",
    "privacyLevel": "private"
  }
}
```
