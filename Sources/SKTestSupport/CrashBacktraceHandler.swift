//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Install a signal handler that prints the backtrace of the crashing thread to stderr when the test
/// process crashes.
///
/// The Swift runtime's backtracer inspects the crashed process from a separate process, which isn't
/// permitted on the macOS CI machines, and these machines don't write crash reports either. This
/// handler prints the backtrace from within the crashing process instead. After printing, it hands
/// the signal to the previously installed handler.
///
/// Installing the handler more than once has no effect.
package func installCrashBacktraceHandler() {
  #if canImport(Darwin) || canImport(Glibc)
  _ = crashBacktraceHandlerInstallation
  #endif
}

#if canImport(Darwin) || canImport(Glibc)

#if canImport(Glibc)
// `execinfo.h`, which declares `backtrace` and `backtrace_symbols_fd`, isn't part of the `Glibc`
// module. Look the functions up at runtime instead.
private typealias BacktraceFunction =
  @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?, Int32) -> Int32
private typealias BacktraceSymbolsFdFunction =
  @convention(c) (UnsafePointer<UnsafeMutableRawPointer?>?, Int32, Int32) -> Void

private let backtraceFunctions: (BacktraceFunction, BacktraceSymbolsFdFunction)? = {
  let handle = dlopen(nil, RTLD_NOW)
  guard let backtrace = dlsym(handle, "backtrace"),
    let backtraceSymbolsFd = dlsym(handle, "backtrace_symbols_fd")
  else {
    return nil
  }
  return (
    unsafeBitCast(backtrace, to: BacktraceFunction.self),
    unsafeBitCast(backtraceSymbolsFd, to: BacktraceSymbolsFdFunction.self)
  )
}()

private func backtrace(_ buffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>, _ size: Int32) -> Int32 {
  return backtraceFunctions?.0(buffer, size) ?? 0
}

private func backtrace_symbols_fd(_ buffer: UnsafePointer<UnsafeMutableRawPointer?>, _ size: Int32, _ fd: Int32) {
  backtraceFunctions?.1(buffer, size, fd)
}
#endif

private let crashSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE]

private let maxBacktraceFrames: Int32 = 128

/// The buffer that the signal handler collects the backtrace into. Allocated up front because
/// allocating memory isn't safe in a signal handler.
private nonisolated(unsafe) let backtraceBuffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>
  .allocate(capacity: Int(maxBacktraceFrames))

/// The signal actions that were installed before the crash handler, indexed by signal number.
private nonisolated(unsafe) let previousActions = UnsafeMutablePointer<sigaction>.allocate(capacity: 64)

private let crashBacktraceHandlerInstallation: Void = {
  // `backtrace` may load the unwinder on its first call, which isn't safe in a signal handler.
  _ = backtrace(backtraceBuffer, maxBacktraceFrames)

  for signal in crashSignals {
    var action = sigaction()
    #if canImport(Darwin)
    action.__sigaction_u.__sa_handler = handleCrashSignal
    #else
    action.__sigaction_handler = .init(sa_handler: handleCrashSignal)
    #endif
    sigemptyset(&action.sa_mask)
    action.sa_flags = 0
    sigaction(signal, &action, previousActions.advanced(by: Int(signal)))
  }
}()

/// Must only call functions that are safe to call in a signal handler.
private func handleCrashSignal(_ signal: Int32) {
  let header: StaticString = "\n*** Test process crashed. Backtrace of the crashing thread:\n"
  header.withUTF8Buffer { buffer in
    _ = write(STDERR_FILENO, buffer.baseAddress, buffer.count)
  }
  let frameCount = backtrace(backtraceBuffer, maxBacktraceFrames)
  backtrace_symbols_fd(backtraceBuffer, frameCount, STDERR_FILENO)

  // Let the previously installed handler, or the default action, handle the crash.
  sigaction(signal, previousActions.advanced(by: Int(signal)), nil)
  raise(signal)
}

#endif
