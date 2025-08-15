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
//

#ifndef SOURCEKITLSP_CSKTESTSUPPORT_H
#define SOURCEKITLSP_CSKTESTSUPPORT_H

#ifdef __linux__
// For testing, override __cxa_atexit to prevent registration of static
// destructors due to https://github.com/swiftlang/swift/issues/55112.
int __cxa_atexit(void (*f) (void *), void *arg, void *dso_handle);
#endif

#endif /* SOURCEKITLSP_CSKTESTSUPPORT_H */
