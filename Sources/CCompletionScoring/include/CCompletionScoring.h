//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#ifndef SOURCEKITLSP_CCOMPLETIONSCORING_H
#define SOURCEKITLSP_CCOMPLETIONSCORING_H

#define _GNU_SOURCE
#include <string.h>

static inline void *sourcekitlsp_memmem(const void *haystack, size_t haystacklen, const void *needle, size_t needlelen) {
  return memmem(haystack, haystacklen, needle, needlelen);
}

#endif // SOURCEKITLSP_CCOMPLETIONSCORING_H
