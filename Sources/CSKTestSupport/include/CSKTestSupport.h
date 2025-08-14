#ifndef CSKTestSupport_h
#define CSKTestSupport_h

#ifdef __linux__
// For testing, override __cxa_atexit to prevent registration of static
// destructors due to https://github.com/swiftlang/swift/issues/55112.
int __cxa_atexit(void (*f) (void *), void *arg, void *dso_handle);
#endif

#endif /* CSKTestSupport_h */
