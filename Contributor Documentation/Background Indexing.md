# Background Indexing

Background indexing is a collective term for two related but fundamentally independent operations that support cross-file and cross-module functionality within a project:
1. Module preparation of a target generates the Swift modules of all the dependent targets so that `import` statements can be resolved, eg. to produce diagnostics for a source file open in the editor.
2. Updating the index store for a source file essentially type checks the source file and writes information about symbol occurrences and their relations to the index store, which will be picked up by indexstore-db. Updating the index store for a source file requires its target to be prepared so that the import statements within can be resolved.

A lot of semantic editor functionality doesn’t require an up-to-date index: For example, code completion operates exclusively on the source file’s AST and thus only requires the file’s target to be prepared but doesn’t use the index store. As a rule of thumb, all functionality that only looks up definitions (like jump-to-definition of a variable) can operate without the index, any functionality that looks for references to a symbol needs the index (like call hierarchy).

## Target preparation

Preparation of a target should perform the minimal amount of work to build all `.swiftmodule` files that the target transitively depends on, so that import statements can be resolved. Errors in dependent targets should not stop downstream modules from being built (this is different to a normal build in which the build is usually stopped if a dependent modules couldn’t be built). For SwiftPM, this is done by invoking `swift build` with the `--experimental-prepare-for-indexing` parameter.

### Status tracking

When SourceKit-LSP is launched, all targets are considered to be out-of-date. This needs to be done because source files might have changed since SourceKit-LSP was last started – if the module wasn’t modified since the last SourceKit-LSP launch, we re-prepare the target and rely on the build system to produce a fast null build.

After we have prepared a target, we mark it as being up-to-date in `SemanticIndexManager.preparationUpToDateTracker`. That way we don’t need to invoke the build system every time we want to perform semantic functionality of a source file, which saves us the time of a null build (which can hundreds of milliseconds for SwiftPM). If a source file is changed (as noted through file watching), all of its target’s dependencies are marked as out-of-date. Note that the target that the source file belongs to is not marked as out-of-date – preparation of a target builds all dependencies but does not need to build the target’s module itself. The next operation that requires the target to be prepared will trigger a preparation job.

## Updating the index store

Updating the index store is done by invoking the compiler for the source file (either `swiftc` or `clang`) with flags that write index data about declared symbols and their occurrences (ie. locations that reference them) to the index store as unit and record files. These unit and record files are watched for by indexstore-db, which is a database on top of the raw index data that allows eg. efficient lookup of the record files that contain the reference to a symbol.

### Status tracking

Similarly to target preparation, when SourceKit-LSP is launched, the index of all source files is considered out-of-date and the initial index of the project is triggered, which indexes every file.

When a source file should be indexed, we first check if a unit file for this source file already exists and whether the date of that unit file is later than the last modification date of the source file. If this is the case, we know that the source file hasn’t been modified since it was last indexed and thus, no work needs to be done – avoiding re-indexing the entire project if it is closed and re-opened. If no unit file exists or if the source file has been modified, the compiler is launched to update the file’s index.

Once we know that a source file’s index is up-to-date, we mark it in `SemanticIndexManager.indexStoreUpToDateTracker`, similar to preparation status tracking. This way we don’t need to hit the file system to check if a source file has an up-to-date index.

## Scheduling of index operations

Target preparation and updating of the index store are guarded on two levels: When the request to prepare a target or update the index of a source file comes in, `SemanticIndexManager` performs a fast check to see if the target or source file is already known to be up-to-date. If so, we can immediately return without having to schedule a task in the `TaskScheduler`.

If we don’t hit this fast path, a new task will be added to the `TaskScheduler` and all dependency tracking, scheduling considerations or in-progress up-to-date tracking is handed over to the task scheduler, the semantic index manager doesn’t need to worry about them. For example:
- The task scheduler will prevent two preparation tasks from running simultaneously because they would access the same build folder.
- The task scheduler will execute tasks with higher priority first.
- The task scheduler will not run two jobs that index the same file simultaneously.
- If two tasks to index the same file have been added to the task scheduler (eg. because the source file was modified twice before the first update job was scheduled), the task scheduler will execute the first index task first. When the second index task is executed, it checks whether the source file’s index is now up-to-date, which is the case here, so the second index operation is a no-op and doesn’t launch a compiler process.

