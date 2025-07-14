//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CCompletionScoring
import Foundation

extension Range where Bound: Numeric {
  init(from: Bound, length: Bound) {
    self = from..<(from + length)
  }

  var length: Bound {
    upperBound - lowerBound
  }

  mutating func extend(upperBoundBy amount: Bound) {
    self = lowerBound..<(upperBound + amount)
  }
}

extension Collection {
  package var only: Element? {
    count == 1 ? first : nil
  }

  package var hasContent: Bool {
    !isEmpty
  }

  func compacted<T>() -> [T] where Element == T? {
    compactMap { $0 }
  }
}

extension Sequence where Element: Numeric {
  package func sum() -> Element {
    reduce(0, +)
  }
}

extension Sequence {
  func sum<I: Numeric>(of valueExtractor: (Element) -> I) -> I {
    reduce(into: 0) { partialResult, element in
      partialResult += valueExtractor(element)
    }
  }
}

extension Sequence {
  func countOf(predicate: (Element) throws -> Bool) rethrows -> Int {
    var count = 0
    for element in self {
      if try predicate(element) {
        count += 1
      }
    }
    return count
  }
}

struct GenericError: Error, LocalizedError {
  var message: String
  init(_ message: String) {
    self.message = message
  }
}

extension Optional {
  package func unwrap(orThrow message: String) throws -> Wrapped {
    if let result = self {
      return result
    }
    throw GenericError(message)
  }

  package func unwrap(orFail message: String) -> Wrapped {
    if let result = self {
      return result
    }
    preconditionFailure(message)
  }

  package mutating func lazyInitialize(initializer: () -> Wrapped) -> Wrapped {
    if let wrapped = self {
      return wrapped
    } else {
      let wrapped = initializer()
      self = wrapped
      return wrapped
    }
  }
}

extension UnsafeBufferPointer {
  init(to element: inout Element) {
    self = withUnsafePointer(to: &element) { pointer in
      UnsafeBufferPointer(start: pointer, count: 1)
    }
  }
}

extension UnsafeBufferPointer {
  package static func allocate(copyOf original: some Collection<Element>) -> Self {
    return Self(UnsafeMutableBufferPointer.allocate(copyOf: original))
  }
}

extension UnsafeMutablePointer {
  mutating func resize(fromCount oldCount: Int, toCount newCount: Int) {
    let replacement = UnsafeMutablePointer.allocate(capacity: newCount)
    let copiedCount = min(oldCount, newCount)
    replacement.moveInitialize(from: self, count: copiedCount)
    let abandondedCount = oldCount - copiedCount
    self.advanced(by: copiedCount).deinitialize(count: abandondedCount)
    deallocate()
    self = replacement
  }

  func initialize(from collection: some Collection<Pointee>) {
    let buffer = UnsafeMutableBufferPointer(start: self, count: collection.count)
    _ = buffer.initialize(from: collection)
  }
}

extension UnsafeMutableBufferPointer {
  package static func allocate(copyOf original: some Collection<Element>) -> Self {
    let copy = UnsafeMutableBufferPointer<Element>.allocate(capacity: original.count)
    _ = copy.initialize(from: original)
    return copy
  }

  package func initialize(index: Int, to value: Element) {
    self.baseAddress!.advanced(by: index).initialize(to: value)
  }

  func deinitializeAll() {
    baseAddress!.deinitialize(count: count)
  }

  package func deinitializeAllAndDeallocate() {
    deinitializeAll()
    deallocate()
  }

  mutating func truncateAndDeinitializeTail(maxLength: Int) {
    if maxLength < count {
      self.baseAddress!.advanced(by: maxLength).deinitialize(count: count - maxLength)
      self = UnsafeMutableBufferPointer(start: baseAddress, count: maxLength)
    }
  }

  mutating func removeAndTruncateWhere(_ predicate: (Element) -> Bool) {
    var writeIndex = 0
    for readIndex in indices {
      if !predicate(self[readIndex]) {
        if writeIndex != readIndex {
          swapAt(writeIndex, readIndex)
        }
        writeIndex += 1
      }
    }
    truncateAndDeinitializeTail(maxLength: writeIndex)
  }

  func setAll(to value: Element) {
    for index in indices {
      self[index] = value
    }
  }
}

infix operator <? : ComparisonPrecedence
infix operator >? : ComparisonPrecedence

extension Comparable {
  /// Useful for chained comparison, for example on a person, sorting by last, first, age:
  /// ```
  /// static func <(_ lhs: Self, _ rhs: Self) -> Bool {
  ///     return lhs.last <? rhs.last
  ///         ?? lhs.first <? rhs.first
  ///         ?? lhs.age <? rhs.age
  /// }
  /// ```
  /// Useful compared to tuple approach with expensive accessors.
  package static func <? (_ lhs: Self, _ rhs: Self) -> Bool? {
    // Assume that `<` is most likely, and avoid a redundant `==`.
    if lhs < rhs {
      return true
    } else if lhs == rhs {
      return nil
    } else {
      return false
    }
  }

  /// See <?
  package static func >? (_ lhs: Self, _ rhs: Self) -> Bool? {
    // Assume that `>` is most likely, and avoid a redundant `==`.
    if lhs > rhs {
      return true
    } else if lhs == rhs {
      return nil
    } else {
      return false
    }
  }
}

infix operator ..+ : RangeFormationPrecedence

package func ..+ <Bound: Numeric>(lhs: Bound, rhs: Bound) -> Range<Bound> {
  lhs..<(lhs + rhs)
}

extension RandomAccessCollection {
  fileprivate func withMapScratchArea<T, R>(body: (UnsafeMutablePointer<T>) -> R) -> R {
    let scratchArea = UnsafeMutablePointer<T>.allocate(capacity: count)
    defer {
      scratchArea.deinitialize(count: count)
      /// Should be a no-op
      scratchArea.deallocate()
    }
    return body(scratchArea)
  }

  package func concurrentCompactMap<T>(_ f: @Sendable (Element) -> T?) -> [T] where Self: Sendable, Index: Sendable {
    return withMapScratchArea { (results: UnsafeMutablePointer<T?>) -> [T] in
      // `nonisolated(unsafe)` is fine because we write to different offsets within the buffer on every concurrent
      // iteration.
      nonisolated(unsafe) let results = results
      DispatchQueue.concurrentPerform(iterations: count) { iterationIndex in
        let collectionIndex = self.index(self.startIndex, offsetBy: iterationIndex)
        results.advanced(by: iterationIndex).initialize(to: f(self[collectionIndex]))
      }
      return UnsafeBufferPointer(start: results, count: count).compacted()
    }
  }

  package func concurrentMap<T>(_ f: @Sendable (Element) -> T) -> [T] where Self: Sendable, Index: Sendable {
    return withMapScratchArea { (results: UnsafeMutablePointer<T>) -> [T] in
      // `nonisolated(unsafe)` is fine because we write to different offsets within the buffer on every concurrent
      // iteration.
      nonisolated(unsafe) let results = results
      DispatchQueue.concurrentPerform(iterations: count) { iterationIndex in
        let collectionIndex = self.index(self.startIndex, offsetBy: iterationIndex)
        results.advanced(by: iterationIndex).initialize(to: f(self[collectionIndex]))
      }
      return Array(UnsafeBufferPointer(start: results, count: count))
    }
  }

  package func max(by accessor: (Element) -> some Comparable) -> Element? {
    self.max { lhs, rhs in
      accessor(lhs) < accessor(rhs)
    }
  }

  package func min(by accessor: (Element) -> some Comparable) -> Element? {
    self.min { lhs, rhs in
      accessor(lhs) < accessor(rhs)
    }
  }

  package func max<T: Comparable>(of accessor: (Element) -> T) -> T? {
    let extreme = self.max { lhs, rhs in
      accessor(lhs) < accessor(rhs)
    }
    return extreme.map(accessor)
  }

  package func min<T: Comparable>(of accessor: (Element) -> T) -> T? {
    let extreme = self.min { lhs, rhs in
      accessor(lhs) < accessor(rhs)
    }
    return extreme.map(accessor)
  }
}

protocol ContiguousZeroBasedIndexedCollection: Collection where Index == Int {
  var indices: Range<Int> { get }
}

#if compiler(<6.2)
/// Provide a compatibility layer for `SendableMetatype` if it doesn't exist in the compiler
typealias SendableMetatype = Any
#endif

extension ContiguousZeroBasedIndexedCollection {
  func slicedConcurrentForEachSliceRange(body: @Sendable (Range<Index>) -> Void) where Self: SendableMetatype {
    // We want to use `DispatchQueue.concurrentPerform`, but we want to be called only a few times. So that we
    // can amortize per-callback work. We also want to oversubscribe so that we can efficiently use
    // heterogeneous CPUs. If we had 4 efficiency cores, and 4 performance cores, and we dispatched 8 work items
    // we'd finish 4 quickly, and then either migrate the work, or leave the performance cores idle. Scheduling
    // extra jobs should let the performance cores pull a disproportionate amount of work items. More fine
    // granularity also helps if the work items aren't all the same difficulty, for the same reason.

    // Defensive against `processorCount` failing
    let sliceCount = Swift.min(Swift.max(ProcessInfo.processInfo.processorCount * 32, 1), count)
    let count = self.count
    DispatchQueue.concurrentPerform(iterations: sliceCount) { sliceIndex in
      precondition(sliceCount >= 1)
      /// Remainder will be distributed across leading slices, so slicing an array with count 5 into 3 slices will give you
      /// slices of size [2, 2, 1].
      let equalPortion = count / sliceCount
      let remainder = count - (equalPortion * sliceCount)
      let getsRemainder = sliceIndex < remainder
      let length = equalPortion + (getsRemainder ? 1 : 0)
      let previousSlicesGettingRemainder = Swift.min(sliceIndex, remainder)
      let start = (sliceIndex * equalPortion) + previousSlicesGettingRemainder
      body(start ..+ length)
    }
  }
}

extension Array: ContiguousZeroBasedIndexedCollection {}
extension UnsafeMutableBufferPointer: ContiguousZeroBasedIndexedCollection {}

extension Array {
  /// A concurrent map that allows amortizing per-thread work. For example, if you need a scratch buffer
  /// to complete the mapping, but could use the same scratch buffer for every iteration on the same thread
  /// you can use this function instead of `concurrentMap`. This method also often helps amortize reference
  /// counting since there are less callbacks
  ///
  /// - Important: The callback must write to all values in `destination[0..<ArraySlice.count]` or the
  ///   output will have uninitialized memory. Remember the array slice indexes aren't zero based.
  ///
  /// A typical `writer` might look like:
  ///
  ///     ```
  ///     for (outputIndex, input) in slice.enumerated() {
  ///         destination.advanced(by: outputIndex).initialize(to: result(of: input))
  ///     }
  ///     ```
  package func unsafeSlicedConcurrentMap<T>(
    writer: @Sendable (ArraySlice<Element>, _ destination: UnsafeMutablePointer<T>) -> Void
  ) -> [T] where Self: Sendable {
    return Array<T>(unsafeUninitializedCapacity: count) { buffer, initializedCount in
      if let bufferBase = buffer.baseAddress {
        // `nonisolated(unsafe)` is fine because every concurrent iteration accesses a disjunct slice of `buffer`.
        nonisolated(unsafe) let bufferBase = bufferBase
        slicedConcurrentForEachSliceRange { sliceRange in
          writer(self[sliceRange], bufferBase.advanced(by: sliceRange.startIndex))
        }
      } else {
        precondition(isEmpty)
      }
      initializedCount = count
    }
  }

  /// Concurrent for-each on self, but slice based to allow the body to amortize work across callbacks
  func slicedConcurrentForEach(body: @Sendable (ArraySlice<Element>) -> Void) where Self: Sendable {
    slicedConcurrentForEachSliceRange { sliceRange in
      body(self[sliceRange])
    }
  }

  func concurrentForEach(body: @Sendable (Element) -> Void) where Self: Sendable {
    DispatchQueue.concurrentPerform(iterations: count) { index in
      body(self[index])
    }
  }

  init(capacity: Int) {
    self = Self()
    reserveCapacity(capacity)
  }

  package init(count: Int, generator: () -> Element) {
    self = (0..<count).map { _ in
      generator()
    }
  }
}

extension Dictionary {
  init(capacity: Int) {
    self = Self()
    reserveCapacity(capacity)
  }

  func mapKeys<K: Hashable>(overwritingDuplicates: Affirmative, _ map: (Key) -> K) -> [K: Value] {
    var result = Dictionary<K, Value>(capacity: count)
    for (key, value) in self {
      result[map(key)] = value
    }
    return result
  }
}

enum Affirmative {
  case affirmative
}

package enum ComparisonOrder: Equatable {
  case ascending
  case same
  case descending

  init(_ value: Int) {
    if value < 0 {
      self = .ascending
    } else if value == 0 {
      self = .same
    } else {
      self = .descending
    }
  }
}

extension UnsafeBufferPointer {
  func afterFirst() -> Self {
    precondition(hasContent)
    return UnsafeBufferPointer(start: baseAddress! + 1, count: count - 1)
  }

  package static func withSingleElementBuffer<R>(
    of element: Element,
    body: (Self) throws -> R
  ) rethrows -> R {
    var element = element
    let typedBufferPointer = Self(to: &element)
    return try body(typedBufferPointer)
  }
}

extension UnsafeBufferPointer<UInt8> {
  package func rangeOf(bytes needle: UnsafeBufferPointer<UInt8>, startOffset: Int = 0) -> Range<Int>? {
    guard count > 0, let baseAddress else {
      return nil
    }
    guard needle.count > 0, let needleBaseAddress = needle.baseAddress else {
      return nil
    }
    guard
      let match = sourcekitlsp_memmem(baseAddress + startOffset, count - startOffset, needleBaseAddress, needle.count)
    else {
      return nil
    }
    let start = baseAddress.distance(to: match.assumingMemoryBound(to: UInt8.self))
    return start ..+ needle.count
  }

  func rangeOf(bytes needle: [UInt8]) -> Range<Int>? {
    needle.withUnsafeBufferPointer { bytes in
      rangeOf(bytes: bytes)
    }
  }
}

func equateBytes(_ lhs: UnsafeBufferPointer<UInt8>, _ rhs: UnsafeBufferPointer<UInt8>) -> Bool {
  compareBytes(lhs, rhs) == .same
}

package func compareBytes(
  _ lhs: UnsafeBufferPointer<UInt8>,
  _ rhs: UnsafeBufferPointer<UInt8>
) -> ComparisonOrder {
  compareBytes(UnsafeRawBufferPointer(lhs), UnsafeRawBufferPointer(rhs))
}

func compareBytes(_ lhs: UnsafeRawBufferPointer, _ rhs: UnsafeRawBufferPointer) -> ComparisonOrder {
  let result = Int(memcmp(lhs.baseAddress!, rhs.baseAddress!, min(lhs.count, rhs.count)))
  return (result != 0) ? ComparisonOrder(result) : ComparisonOrder(lhs.count - rhs.count)
}

extension String {
  /// Non mutating version of withUTF8. withUTF8 is mutating to make the string contiguous, so that future calls will
  /// be cheaper.
  /// Useful when you're operating on an argument, and have no way to avoid this copy dance.
  package func withUncachedUTF8Bytes<R>(
    _ body: (
      UnsafeBufferPointer<UTF8Byte>
    ) throws -> R
  ) rethrows -> R {
    var copy = self
    return try copy.withUTF8(body)
  }
}
