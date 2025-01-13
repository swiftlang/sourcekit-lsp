# Using SourceKit-LSP with Embedded Projects

If you need to pass additional options in the `swift build` invocation to build your project, SourceKit-LSP needs to know about these as well to fully understand your project. To tell SourceKit-LSP about these options, add a `.sourcekit-lsp/config.json` file to your project’s root folder and add the arguments you pass to `swift build` to that configuration file as described [here](Configuration%20File.md).

For example, if you use the following invocation to build your project

```sh
swift build \
  --configuration release \
  --triple armv7em-apple-none-macho \
  -Xcc -D__APPLE__ -Xcc -D__MACH__ \
  -Xswiftc -Xfrontend -Xswiftc -disable-stack-protector
```

Then the `.sourcekit-lsp/config.json` file should contain

```json
{
  "swiftPM": {
    "configuration": "release",
    "triple": "armv7em-apple-none-macho",
    "cCompilerFlags": ["-D__APPLE__", "-D__MACH__"],
    "swiftCompilerFlags": ["-Xfrontend", "-disable-stack-protector"]
  }
}
```
