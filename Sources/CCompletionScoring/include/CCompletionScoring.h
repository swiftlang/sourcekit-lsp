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

static inline void *sourcekitlsp_memmem(const void *haystack, size_t haystack_len, const void *needle, size_t needle_len) {
  #if defined(_WIN32) && !defined(__CYGWIN__)
  // memmem is not available on Windows
  if (!haystack || haystack_len == 0) {
    return NULL;
  }
  if (!needle || needle_len == 0) {
    return NULL;
  }
  if (needle_len > haystack_len) {
    return NULL;
  }

  for (size_t offset = 0; offset <= haystack_len - needle_len; ++offset) {
    if (memcmp(haystack + offset, needle, needle_len) == 0) {
      return (void *)haystack + offset;
    }
  }
  return NULL;
  #else
  return memmem(haystack, haystack_len, needle, needle_len);
  #endif
}

#endif // SOURCEKITLSP_CCOMPLETIONSCORING_H
