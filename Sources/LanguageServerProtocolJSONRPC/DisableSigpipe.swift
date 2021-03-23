//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//


#if canImport(Glibc)
import Glibc
#endif

#if os(Linux) || os(Android)
// This is a lazily initialised global variable that when read for the first time, will ignore SIGPIPE.
private let globallyIgnoredSIGPIPE: Bool = {
    /* no F_SETNOSIGPIPE on Linux :( */
    _ = Glibc.signal(SIGPIPE, SIG_IGN)
    return true
}()

internal func globallyDisableSigpipe() {
  let haveWeIgnoredSIGPIEThisIsHereToTriggerIgnoringIt = globallyIgnoredSIGPIPE
  guard haveWeIgnoredSIGPIEThisIsHereToTriggerIgnoringIt else {
    fatalError("globallyIgnoredSIGPIPE should always be true")
  }
}

#endif
