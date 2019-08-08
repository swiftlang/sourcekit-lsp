// Note: tests generally should avoid including system headers
// to keep them fast and portable. This test is specifically
// ensuring clangd can find libc++ and builtin headers.

#include <cstdint>

void test() {
  uint64_t /*unused_b*/b/*<unused_b:end*/;
}
