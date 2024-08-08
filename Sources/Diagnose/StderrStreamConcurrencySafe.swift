//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class TSCBasic.LocalFileOutputByteStream
import class TSCBasic.ThreadSafeOutputByteStream

#if canImport(Darwin)
import TSCLibc
#else
// TODO: @preconcurrency needed because stderr is not sendable on Linux https://github.com/swiftlang/swift/issues/75601
@preconcurrency import TSCLibc
#endif

// A version of `stderrStream` from `TSCBasic` that is a `let` and can thus be used from Swift 6.
let stderrStreamConcurrencySafe: ThreadSafeOutputByteStream = try! ThreadSafeOutputByteStream(
  LocalFileOutputByteStream(
    filePointer: TSCLibc.stderr,
    closeOnDeinit: false
  )
)
