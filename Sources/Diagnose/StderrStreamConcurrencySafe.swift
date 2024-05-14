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

import TSCLibc

import class TSCBasic.LocalFileOutputByteStream
import class TSCBasic.ThreadSafeOutputByteStream

// A version of `stderrStream` from `TSCBasic` that is a `let` and can thus be used from Swift 6.
let stderrStreamConcurrencySafe: ThreadSafeOutputByteStream = try! ThreadSafeOutputByteStream(
  LocalFileOutputByteStream(
    filePointer: TSCLibc.stderr,
    closeOnDeinit: false
  )
)
