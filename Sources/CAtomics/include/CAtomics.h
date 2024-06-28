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

#ifndef SOURCEKITLSP_CATOMICS_H
#define SOURCEKITLSP_CATOMICS_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>
#include <stdlib.h>

typedef struct {
  _Atomic(uint32_t) value;
} CAtomicUInt32;

static inline CAtomicUInt32 *_Nonnull atomic_uint32_create(uint32_t initialValue) {
  CAtomicUInt32 *atomic = malloc(sizeof(CAtomicUInt32));
  atomic->value = initialValue;
  return atomic;
}

static inline uint32_t atomic_uint32_get(CAtomicUInt32 *_Nonnull atomic) {
  return atomic->value;
}

static inline void atomic_uint32_set(CAtomicUInt32 *_Nonnull atomic, uint32_t newValue) {
  atomic->value = newValue;
}

static inline uint32_t atomic_uint32_fetch_and_increment(CAtomicUInt32 *_Nonnull atomic) {
  return atomic->value++;
}

static inline void atomic_uint32_destroy(CAtomicUInt32 *_Nonnull atomic) {
  free(atomic);
}

#endif // SOURCEKITLSP_CATOMICS_H
