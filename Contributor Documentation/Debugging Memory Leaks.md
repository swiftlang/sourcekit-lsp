# Debugging Memory Leaks

https://www.swift.org/documentation/server/guides/memory-leaks-and-usage.html is a good document with instructions on how to debug memory leaks in Swift. Below are some steps tailored to debug SourceKit-LSP.

## macOS

At any point during SourceKit-LSP’s execution, you can collect a memory graph using

```bash
leaks --outputGraph=/tmp sourcekit-lsp
```

This memory graph can then be opened in Xcode to inspect which objects are alive at that point in time and which objects reference them (thus keeping them alive).

## Linux

[heaptrack](https://github.com/KDE/heaptrack) is a helpful tool to monitor memory allocations and leaks. To debug a memory leak on Linux you need to have SourceKit-LSP (and potentially sourcekitd) built from source, because heaptrack requires debug information for the binaries it inspects. To debug a memory issue on Linux.

- Install heaptrack: `apt install heaptrack heaptrack-gui`
- Attach heaptrack to SourceKit-LSP: `heaptrack --record-only --pid $(pidof sourcekit-lsp)`
- Run the command that heaptrack suggests to analyze the file
