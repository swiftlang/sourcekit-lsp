#!/usr/bin/env bash
# Build sourcekit-lsp on Linux. The indexstore-db dependency needs dispatch and Block
# headers from the Swift toolchain; this script passes the right include paths.
set -e
RUNTIME=$(swift -print-target-info 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['paths']['runtimeLibraryPaths'][0])" 2>/dev/null)
SWIFT_LIB=$(dirname "$RUNTIME")
if [[ -z "$SWIFT_LIB" || ! -d "$SWIFT_LIB" ]]; then
  echo "Could not detect Swift runtime library path. Run: swift -print-target-info"
  exit 1
fi
# indexstore-db's Concurrency-Mac.cpp expects <dispatch/dispatch.h> and <Block.h>
INCLUDES="-Xcxx -I$SWIFT_LIB -Xcxx -I$SWIFT_LIB/Block"
echo "Using Swift lib path: $SWIFT_LIB"
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "test" ]]; then
  swift test $INCLUDES "${@:2}"
else
  swift build $INCLUDES "$@"
fi
