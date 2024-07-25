# Which files to re-index when a file is modified

## `.swift`

Obviously affects the file itself, which we do re-index.

If an internal declaration was changed, all files within the module might be also affected. If a public declaration was changed, all modules that depend on it might be affected. The effect can only really be in three ways:
1. It might change overload resolution in another file, which is fairly unlikely
2. A new declaration is introduced in this file that is already referenced by another file
3. A declaration is removed in this file that was referenced from other files. In those cases the other files now have an invalid reference.

We decided to not re-index any files other than the file itself because naively re-indexing all files that might depend on the modified file requires too much processing power that will likely have no or very little effect on the index – we are trading accuracy for CPU time here.
We mark the targets of the changed file as well as any dependent targets as out-of-date. The assumption is that most likely the user will go back to any of the affected files shortly afterwards and modify them again. When that happens, the affected file will get re-indexed and bring the index back up to date.

Alternatives would be:
- We could we check the file’s interface hash and re-index other files based on whether it has changed. But at that point we are somewhat implementing a build system. And even if a new public method was introduced it’s very likely that the user hasn’t actually used it anywhere yet, which means that re-indexing all dependent modules would still be doing unnecessary work.
- To cover case (2) from above, we could re-index only dependencies that previously indexed with errors. This is an alternative that hasn’t been fully explored.

## `.h`

All files that include the header (including via other headers) might be affected by the change, similar to how all `.swift` files that import a module might be affected. Similar to modules, we choose to not re-index all files that include the header because of the same considerations mentioned above.

To re-index the header, we pick one main file that includes the header and re-index that, which will effectively update the index for the header. For existing headers, we know which files import a header from the existing index. For new header files, we assume that it hasn’t been included in any file yet and thus don't index it. If the user wrote an include to the new header before creating the header itself, we don't know about that include from the existing index. But it’s likely that the user will modify the file that includes the new header file shortly after, which will index the header and establish the header to main file connection.

## `.c` / `.cpp` / `.m`

This is the easy case since only the file itself is affected.

## Compiler settings (`compile_commands.json` / `Package.swift`)

Ideally, we would like to consider a file as changed when its compile commands have changed, if they changed in a meaningful way (ie. in a way that would also trigger re-compilation in an incremental build). Non-meaningful changes would be:
- If compiler arguments that aren't order dependent are shuffled around. We could have a really quick check for compiler arguments equality by comparing them unordered. Any real compiler argument change will most likely do more than rearranging the arguments.
- The addition of a new Swift file to a target is equivalent to that file being modified and shouldn’t trigger a re-index of the entire target.

At the moment, unit files don’t include information about the compiler arguments with which they were created, so it’s impossible to know whether the compiler arguments have changed when a project is opened. Thus, for now, we don’t re-index any files on compiler settings changing.
