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

import Foundation

/// A list of possible code completion results that need to be culled and sorted based on a ``Pattern``.
package struct CandidateBatch: Sendable {
  package typealias UTF8Bytes = Pattern.UTF8Bytes
  package typealias ContentType = Candidate.ContentType

  /// Clients can access this via `CandidateBatch.withUnsafeStorage()` so that they can have read-access without the
  /// overhead of runtime exclusitivy checks that happen when you read through a reference type.
  package struct UnsafeStorage {
    var bytes: UnsafeArray<UInt8>
    var candidateByteOffsets: UnsafeArray<Int>
    var filters: UnsafeArray<RejectionFilter>
    var contentTypes: UnsafeArray<ContentType>

    private init(
      bytes: UnsafeArray<UInt8>,
      candidateByteOffsets: UnsafeArray<Int>,
      filters: UnsafeArray<RejectionFilter>,
      contentTypes: UnsafeArray<ContentType>
    ) {
      self.bytes = bytes
      self.candidateByteOffsets = candidateByteOffsets
      self.filters = filters
      self.contentTypes = contentTypes
    }

    static func allocate(candidateCapacity: Int, byteCapacity: Int) -> Self {
      var candidateByteOffsets = UnsafeArray<Int>.allocate(initialCapacity: candidateCapacity + 1)
      candidateByteOffsets.append(0)  // Always contains the 'endIndex'
      return Self(
        bytes: UnsafeArray.allocate(initialCapacity: byteCapacity),
        candidateByteOffsets: candidateByteOffsets,
        filters: UnsafeArray.allocate(initialCapacity: candidateCapacity),
        contentTypes: UnsafeArray.allocate(initialCapacity: candidateCapacity)
      )
    }

    mutating func deallocate() {
      bytes.deallocate()
      candidateByteOffsets.deallocate()
      filters.deallocate()
      contentTypes.deallocate()
    }

    func allocateCopy() -> Self {
      return Self(
        bytes: bytes.allocateCopy(preservingCapacity: true),
        candidateByteOffsets: candidateByteOffsets.allocateCopy(preservingCapacity: true),
        filters: filters.allocateCopy(preservingCapacity: true),
        contentTypes: contentTypes.allocateCopy(preservingCapacity: true)
      )
    }

    @inline(__always)
    func bytes(at index: Int) -> UTF8Bytes {
      let position = candidateByteOffsets[index]
      let nextPosition = candidateByteOffsets[index + 1]
      return UnsafeBufferPointer(start: bytes.elements.advanced(by: position), count: nextPosition - position)
    }

    @inline(__always)
    func candidateContent(at index: Int) -> (UTF8Bytes, ContentType) {
      let position = candidateByteOffsets[index]
      let nextPosition = candidateByteOffsets[index + 1]
      let bytes = UnsafeBufferPointer(
        start: bytes.elements.advanced(by: position),
        count: nextPosition - position
      )
      let contentType = contentTypes[index]
      return (bytes, contentType)
    }

    var count: Int {
      filters.count
    }

    package var indices: Range<Int> {
      return 0..<count
    }

    @inline(__always)
    package func candidate(at index: Int) -> Candidate {
      Candidate(bytes: bytes(at: index), contentType: contentTypes[index], rejectionFilter: filters[index])
    }

    /// Don't add a method that returns a candidate, the candidates have unsafe pointers back into the batch, and
    /// must not outlive it.
    @inline(__always)
    func enumerate(body: (Candidate) throws -> ()) rethrows {
      for idx in 0..<count {
        try body(candidate(at: idx))
      }
    }

    func enumerate(_ range: Range<Int>, body: (Int, Candidate) throws -> ()) rethrows {
      precondition(range.lowerBound >= 0)
      precondition(range.upperBound <= count)
      for idx in range {
        try body(idx, candidate(at: idx))
      }
    }

    subscript(stringAt index: Int) -> String {
      // Started as a valid string, so UTF8 must be valid, if this ever fails (would have to be something like a
      // string with unvalidated content), we should fix it on the input side, not here.
      return String(bytes: bytes(at: index), encoding: .utf8).unwrap(orFail: "Invalid UTF8 Sequence")
    }

    mutating func append(_ candidate: String, contentType: ContentType) {
      candidate.withUncachedUTF8Bytes { bytes in
        append(candidateBytes: bytes, contentType: contentType, rejectionFilter: RejectionFilter(bytes: bytes))
      }
    }

    mutating func append(_ candidate: Candidate) {
      append(
        candidateBytes: candidate.bytes,
        contentType: candidate.contentType,
        rejectionFilter: candidate.rejectionFilter
      )
    }

    mutating func append(_ bytes: UTF8Bytes, contentType: ContentType) {
      append(Candidate(bytes: bytes, contentType: contentType, rejectionFilter: .init(bytes: bytes)))
    }

    mutating func append(
      candidateBytes: some Collection<UTF8Byte>,
      contentType: ContentType,
      rejectionFilter: RejectionFilter
    ) {
      bytes.append(contentsOf: candidateBytes)
      filters.append(rejectionFilter)
      contentTypes.append(contentType)
      candidateByteOffsets.append(bytes.count)
    }

    mutating func append(contentsOf candidates: [String], contentType: ContentType) {
      filters.reserve(minimumAdditionalCapacity: candidates.count)
      contentTypes.reserve(minimumAdditionalCapacity: candidates.count)
      candidateByteOffsets.reserve(minimumAdditionalCapacity: candidates.count)
      for text in candidates {
        append(text, contentType: contentType)
      }
    }

    mutating func append(contentsOf candidates: [UTF8Bytes], contentType: ContentType) {
      filters.reserve(minimumAdditionalCapacity: candidates.count)
      contentTypes.reserve(minimumAdditionalCapacity: candidates.count)
      candidateByteOffsets.reserve(minimumAdditionalCapacity: candidates.count)
      for text in candidates {
        append(text, contentType: contentType)
      }
    }
  }

  private final class StorageBox {
    /// Column oriented data for better cache performance.
    var storage: UnsafeStorage

    private init(storage: UnsafeStorage) {
      self.storage = storage
    }

    init(candidateCapacity: Int, byteCapacity: Int) {
      storage = UnsafeStorage.allocate(candidateCapacity: candidateCapacity, byteCapacity: byteCapacity)
    }

    func copy() -> Self {
      Self(storage: storage.allocateCopy())
    }

    deinit {
      storage.deallocate()
    }
  }

  // `nonisolated(unsafe)` is fine because this `CandidateBatch` is the only struct with access to the `StorageBox`.
  // All mutating access go through `mutate`, which copies `StorageBox` if `CandidateBatch` is not uniquely
  // referenced.
  nonisolated(unsafe) private var __storageBox_useAccessor: StorageBox
  private var readonlyStorage: UnsafeStorage {
    __storageBox_useAccessor.storage
  }

  package init(byteCapacity: Int) {
    self.init(candidateCapacity: byteCapacity / 16, byteCapacity: byteCapacity)
  }

  private init(candidateCapacity: Int, byteCapacity: Int) {
    __storageBox_useAccessor = StorageBox(candidateCapacity: candidateCapacity, byteCapacity: byteCapacity)
  }

  package init() {
    self.init(candidateCapacity: 0, byteCapacity: 0)
  }

  package init(candidates: [String], contentType: ContentType) {
    let byteCapacity = candidates.reduce(into: 0) { sum, string in
      sum += string.utf8.count
    }
    self.init(candidateCapacity: candidates.count, byteCapacity: byteCapacity)
    append(contentsOf: candidates, contentType: contentType)
  }

  package init(candidates: [UTF8Bytes], contentType: ContentType) {
    let byteCapacity = candidates.reduce(into: 0) { sum, candidate in
      sum += candidate.count
    }
    self.init(candidateCapacity: candidates.count, byteCapacity: byteCapacity)
    append(contentsOf: candidates, contentType: contentType)
  }

  package func enumerate(body: (Candidate) throws -> ()) rethrows {
    try readonlyStorage.enumerate(body: body)
  }

  package func enumerate(body: (Int, Candidate) throws -> ()) rethrows {
    try readonlyStorage.enumerate(0..<count, body: body)
  }

  internal func enumerate(_ range: Range<Int>, body: (Int, Candidate) throws -> ()) rethrows {
    try readonlyStorage.enumerate(range, body: body)
  }

  package func withAccessToCandidate<R>(at idx: Int, body: (Candidate) throws -> R) rethrows -> R {
    try withUnsafeStorage { storage in
      try body(storage.candidate(at: idx))
    }
  }

  package func withAccessToBytes<R>(at idx: Int, body: (UTF8Bytes) throws -> R) rethrows -> R {
    try withUnsafeStorage { storage in
      try body(storage.bytes(at: idx))
    }
  }

  package func withUnsafeStorage<R>(_ body: (UnsafeStorage) throws -> R) rethrows -> R {
    try withExtendedLifetime(__storageBox_useAccessor) {
      try body(__storageBox_useAccessor.storage)
    }
  }

  static func withUnsafeStorages<R>(_ batches: [Self], _ body: (UnsafeBufferPointer<UnsafeStorage>) -> R) -> R {
    withExtendedLifetime(batches) {
      withUnsafeTemporaryAllocation(of: UnsafeStorage.self, capacity: batches.count) { storages in
        for (index, batch) in batches.enumerated() {
          storages.initialize(index: index, to: batch.readonlyStorage)
        }
        let result = body(UnsafeBufferPointer(storages))
        storages.deinitializeAll()
        return result
      }
    }
  }

  package subscript(stringAt index: Int) -> String {
    readonlyStorage[stringAt: index]
  }

  package var count: Int {
    return readonlyStorage.count
  }

  package var indices: Range<Int> {
    return readonlyStorage.indices
  }

  var hasContent: Bool {
    count > 0
  }

  private mutating func mutate(body: (inout UnsafeStorage) -> ()) {
    if !isKnownUniquelyReferenced(&__storageBox_useAccessor) {
      __storageBox_useAccessor = __storageBox_useAccessor.copy()
    }
    body(&__storageBox_useAccessor.storage)
  }

  package mutating func append(_ candidate: String, contentType: ContentType) {
    mutate { storage in
      storage.append(candidate, contentType: contentType)
    }
  }

  package mutating func append(_ candidate: Candidate) {
    mutate { storage in
      storage.append(candidate)
    }
  }

  package mutating func append(_ candidate: UTF8Bytes, contentType: ContentType) {
    mutate { storage in
      storage.append(candidate, contentType: contentType)
    }
  }

  package mutating func append(contentsOf candidates: [String], contentType: ContentType) {
    mutate { storage in
      storage.append(contentsOf: candidates, contentType: contentType)
    }
  }

  package mutating func append(contentsOf candidates: [UTF8Bytes], contentType: ContentType) {
    mutate { storage in
      storage.append(contentsOf: candidates, contentType: contentType)
    }
  }

  package func filter(keepWhere predicate: (Int, Candidate) -> Bool) -> CandidateBatch {
    var copy = CandidateBatch()
    enumerate { index, candidate in
      if predicate(index, candidate) {
        copy.append(candidate)
      }
    }
    return copy
  }
}

extension Pattern {
  package struct CandidateBatchesMatch: Equatable, CustomStringConvertible {
    package var batchIndex: Int
    package var candidateIndex: Int
    package var textScore: Double

    package init(batchIndex: Int, candidateIndex: Int, textScore: Double) {
      self.batchIndex = batchIndex
      self.candidateIndex = candidateIndex
      self.textScore = textScore
    }

    package var description: String {
      "CandidateBatchesMatch(batch: \(batchIndex), candidateIndex: \(candidateIndex), score: \(textScore))"
    }
  }

  /// Represents work to be done by each thread when parallelizing scoring. The work is divided ahead of time to maximize memory locality.
  /// Represents work to be done by each thread when parallelizing scoring.
  /// The work is divided ahead of time to maximize memory locality.
  ///
  /// If we have 3 threads, A, B, and C, and 9 things to match, we want to assign the work like AAABBBCCC, not ABCABCABC, to maximize memory locality.
  /// So if we had 2 candidate batches of 8 candidates each, and 3 threads, the new code divides them like [AAAAABBB][BBCCCCCC]
  /// We expect parallelism in the ballpark of 4-64 threads, and the number of candidates to be in the 1,000-100,000 range.
  /// So the remainder of having 1 thread process a few extra candidates doesn't matter.
  ///
  ///
  /// Equatable for testing.
  package struct ScoringWorkload: Equatable {
    package struct CandidateBatchSlice: Equatable {
      var batchIndex: Int
      var candidateRange: Range<Int>

      package init(batchIndex: Int, candidateRange: Range<Int>) {
        self.batchIndex = batchIndex
        self.candidateRange = candidateRange
      }
    }
    /// When scoring and matching and storing the results in a shared buffer, this is the base output index for this
    /// thread workload.
    var outputStartIndex: Int
    var slices: [CandidateBatchSlice] = []

    package init(outputStartIndex: Int, slices: [CandidateBatchSlice] = []) {
      self.outputStartIndex = outputStartIndex
      self.slices = slices
    }

    package static func workloads(
      for batches: [CandidateBatch],
      parallelism threads: Int
    )
      -> [ScoringWorkload]
    {  // Internal for testing.
      let crossBatchCandidateCount = totalCandidates(batches: batches)
      let budgetPerScoringWorkload = crossBatchCandidateCount / threads
      let budgetPerScoringWorkloadRemainder = crossBatchCandidateCount - (budgetPerScoringWorkload * threads)

      var batchIndex = 0
      var candidateIndexInBatch = 0
      var workloads: [ScoringWorkload] = []
      var globalOutputIndex = 0
      for workloadIndex in 0..<threads {
        let isLast = (workloadIndex == (threads - 1))
        var budgetRemaining = budgetPerScoringWorkload + (isLast ? budgetPerScoringWorkloadRemainder : 0)
        var workload = ScoringWorkload(outputStartIndex: globalOutputIndex)
        while budgetRemaining != 0 {
          let batch = batches[batchIndex]
          let spent = min(budgetRemaining, batch.count - candidateIndexInBatch)
          if spent != 0 {
            workload.slices.append(
              .init(batchIndex: batchIndex, candidateRange: candidateIndexInBatch ..+ spent)
            )
            globalOutputIndex += spent
            candidateIndexInBatch += spent
            budgetRemaining -= spent
          }
          if candidateIndexInBatch == batch.count {
            candidateIndexInBatch = 0
            batchIndex += 1
          }
        }
        if workload.slices.hasContent {
          workloads.append(workload)
        }
      }
      // Assert that we terminate after the last batch, with output index assigments for every candidate.
      let lastBatchIndexWithContent = batches.lastIndex(where: \.hasContent) ?? -1
      precondition(batchIndex == lastBatchIndexWithContent + 1)
      precondition(candidateIndexInBatch == 0)
      precondition(globalOutputIndex == crossBatchCandidateCount)
      return workloads
    }
  }

  private static func totalCandidates(batches: [CandidateBatch]) -> Int {
    batches.reduce(into: 0) { sum, batch in
      sum += batch.count
    }
  }

  /// Find all of the matches across `batches` and score them, returning the scored results.
  ///
  /// This is a first part of selecting matches. Later the matches will be combined with matches from other providers,
  /// where we'll pick the best matches and sort them with `selectBestMatches(from:textProvider:)`
  package func scoredMatches(across batches: [CandidateBatch], precision: Precision) -> [CandidateBatchesMatch] {
    compactScratchArea(capacity: Self.totalCandidates(batches: batches)) { matchesScratchArea in
      let scoringWorkloads = ScoringWorkload.workloads(
        for: batches,
        parallelism: ProcessInfo.processInfo.processorCount
      )
      // `nonisolated(unsafe)` is fine because every iteration accesses a distinct index of the buffer.
      nonisolated(unsafe) let matchesScratchArea = matchesScratchArea
      scoringWorkloads.concurrentForEach { threadWorkload in
        UnsafeStackAllocator.withUnsafeStackAllocator { allocator in
          var outputIndex = threadWorkload.outputStartIndex
          for slice in threadWorkload.slices {
            batches[slice.batchIndex].enumerate(slice.candidateRange) { candidateIndex, candidate in
              assert(matchesScratchArea[outputIndex] == nil)
              if let score = self.matchAndScore(
                candidate: candidate,
                precision: precision,
                allocator: &allocator
              ) {
                matchesScratchArea[outputIndex] = CandidateBatchesMatch(
                  batchIndex: slice.batchIndex,
                  candidateIndex: candidateIndex,
                  textScore: score.value
                )
              }
              outputIndex += 1
            }
          }
        }
      }
    }
  }

  package struct CandidateBatchMatch: Equatable {
    package var candidateIndex: Int
    package var textScore: Double

    package init(candidateIndex: Int, textScore: Double) {
      self.candidateIndex = candidateIndex
      self.textScore = textScore
    }
  }

  package func scoredMatches(in batch: CandidateBatch, precision: Precision) -> [CandidateBatchMatch] {
    scoredMatches(across: [batch], precision: precision).map { multiMatch in
      CandidateBatchMatch(candidateIndex: multiMatch.candidateIndex, textScore: multiMatch.textScore)
    }
  }
}

/// A single potential code completion result that can be scored against a ``Pattern``.
package struct Candidate {
  package enum ContentType: Equatable {
    /// A symbol found by code completion.
    case codeCompletionSymbol
    /// The name of a file in the project.
    case fileName
    /// A symbol defined in the project, which can be found by eg. the workspace symbols request.
    case projectSymbol
    case unknown
  }

  package let bytes: Pattern.UTF8Bytes
  package let contentType: ContentType
  let rejectionFilter: RejectionFilter

  package static func withAccessToCandidate<R>(
    for text: String,
    contentType: ContentType,
    body: (Candidate) throws -> R
  )
    rethrows -> R
  {
    var text = text
    return try text.withUTF8 { bytes in
      return try body(.init(bytes: bytes, contentType: contentType, rejectionFilter: .init(bytes: bytes)))
    }
  }

  /// For debugging
  internal var text: String {
    String(bytes: bytes, encoding: .utf8).unwrap(orFail: "UTF8 was prevalidated.")
  }
}

// Creates a buffer of `capacity` elements of type `T?`, each initially set to nil.
///
/// After running `initialize`, returns all elements that were set to non-`nil` values.
private func compactScratchArea<T>(capacity: Int, initialize: (UnsafeMutablePointer<T?>) -> ()) -> [T] {
  let scratchArea = UnsafeMutablePointer<T?>.allocate(capacity: capacity)
  scratchArea.initialize(repeating: nil, count: capacity)
  defer {
    scratchArea.deinitialize(count: capacity)  // Should be a no-op
    scratchArea.deallocate()
  }
  initialize(scratchArea)
  return UnsafeMutableBufferPointer(start: scratchArea, count: capacity).compacted()
}

extension Candidate: CustomStringConvertible {
  package var description: String {
    return String(bytes: bytes, encoding: .utf8) ?? "(Invalid UTF8 Sequence)"
  }
}

extension Candidate {
  @available(*, deprecated, message: "Pass an explicit content type")
  package static func withAccessToCandidate<R>(for text: String, body: (Candidate) throws -> R) rethrows -> R {
    try withAccessToCandidate(for: text, contentType: .codeCompletionSymbol, body: body)
  }
}

extension CandidateBatch: Equatable {
  package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    (lhs.count == rhs.count)
      && lhs.indices.allSatisfy { index in
        lhs.withAccessToCandidate(at: index) { lhs in
          rhs.withAccessToCandidate(at: index) { rhs in
            return equateBytes(lhs.bytes, rhs.bytes)
              && lhs.contentType == rhs.contentType
              && lhs.rejectionFilter == rhs.rejectionFilter
          }
        }
      }
  }
}

extension CandidateBatch {
  @available(*, deprecated, message: "Pass an explicit content type")
  package init(candidates: [String] = []) {
    self.init(candidates: candidates, contentType: .codeCompletionSymbol)
  }

  @available(*, deprecated, message: "Pass an explicit content type")
  package mutating func append(_ candidate: String) {
    append(candidate, contentType: .codeCompletionSymbol)
  }
  @available(*, deprecated, message: "Pass an explicit content type")
  package mutating func append(_ candidate: UTF8Bytes) {
    append(candidate, contentType: .codeCompletionSymbol)
  }
  @available(*, deprecated, message: "Pass an explicit content type")
  package mutating func append(contentsOf candidates: [String]) {
    append(contentsOf: candidates, contentType: .codeCompletionSymbol)
  }
}
