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

// MARK: - AtomicBool

typedef struct {
  _Atomic(bool) value;
} AtomicBool;

__attribute__((swift_name("AtomicBool.init(initialValue:)")))
static inline AtomicBool atomic_bool_create(bool initialValue) {
  AtomicBool atomic;
  atomic.value = initialValue;
  return atomic;
}

__attribute__((swift_name("getter:AtomicBool.value(self:)")))
static inline bool atomic_bool_get(AtomicBool *atomic) {
  return atomic->value;
}

__attribute__((swift_name("setter:AtomicBool.value(self:_:)")))
static inline void atomic_bool_set(AtomicBool *atomic, bool newValue) {
  atomic->value = newValue;
}

// MARK: - AtomicUInt8

typedef struct {
  _Atomic(uint8_t) value;
} AtomicUInt8;

__attribute__((swift_name("AtomicUInt8.init(initialValue:)")))
static inline AtomicUInt8 atomic_uint8_create(uint8_t initialValue) {
  AtomicUInt8 atomic;
  atomic.value = initialValue;
  return atomic;
}

__attribute__((swift_name("getter:AtomicUInt8.value(self:)")))
static inline uint8_t atomic_uint8_get(AtomicUInt8 *atomic) {
  return atomic->value;
}

__attribute__((swift_name("setter:AtomicUInt8.value(self:_:)")))
static inline void atomic_uint8_set(AtomicUInt8 *atomic, uint8_t newValue) {
  atomic->value = newValue;
}

#endif // SOURCEKITLSP_CATOMICS_H
