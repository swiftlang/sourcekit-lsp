//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import IndexStoreDB
import LSPLogging
import LanguageServerProtocol

public enum IndexCheckLevel {
  /// Consider the index out-of-date only if the source file has been deleted on disk.
  ///
  /// This is usually a good default because: When a file gets modified, it's likely that some of the line:column
  /// locations in it are still correct – eg. if only one line is modified and if lines are inserted/deleted all
  /// locations above are still correct.
  /// For locations that are out of date, showing stale results is one of the best ways of communicating to the user
  /// that the index is out-of-date and that they need to rebuild. We might want to reconsider this default when we have
  /// background indexing.
  case deletedFiles

  /// Consider the index out-of-date if the source file has been deleted or modified on disk.
  case modifiedFiles

  /// Consider the index out-of-date if the source file has been deleted or modified on disk or if there are
  /// in-memory modifications in the given `DocumentManager`.
  case inMemoryModifiedFiles(DocumentManager)
}

/// A wrapper around `IndexStoreDB` that checks if returned symbol occurrences are up-to-date with regard to a
/// `IndexCheckLevel`.
///
/// - SeeAlso: Comment on `IndexOutOfDateChecker`
public class CheckedIndex {
  private var checker: IndexOutOfDateChecker
  private let index: IndexStoreDB

  fileprivate init(index: IndexStoreDB, checkLevel: IndexCheckLevel) {
    self.index = index
    self.checker = IndexOutOfDateChecker(checkLevel: checkLevel)
  }

  @discardableResult
  public func forEachSymbolOccurrence(
    byUSR usr: String,
    roles: SymbolRole,
    _ body: @escaping (SymbolOccurrence) -> Bool
  ) -> Bool {
    index.forEachSymbolOccurrence(byUSR: usr, roles: roles) { occurrence in
      guard self.checker.isUpToDate(occurrence.location) else {
        return true  // continue
      }
      return body(occurrence)
    }
  }

  public func occurrences(ofUSR usr: String, roles: SymbolRole) -> [SymbolOccurrence] {
    return index.occurrences(ofUSR: usr, roles: roles).filter { checker.isUpToDate($0.location) }
  }

  public func occurrences(relatedToUSR usr: String, roles: SymbolRole) -> [SymbolOccurrence] {
    return index.occurrences(relatedToUSR: usr, roles: roles).filter { checker.isUpToDate($0.location) }
  }

  @discardableResult public func forEachCanonicalSymbolOccurrence(
    containing pattern: String,
    anchorStart: Bool,
    anchorEnd: Bool,
    subsequence: Bool,
    ignoreCase: Bool,
    body: @escaping (SymbolOccurrence) -> Bool
  ) -> Bool {
    index.forEachCanonicalSymbolOccurrence(
      containing: pattern,
      anchorStart: anchorStart,
      anchorEnd: anchorEnd,
      subsequence: subsequence,
      ignoreCase: ignoreCase
    ) { occurrence in
      guard self.checker.isUpToDate(occurrence.location) else {
        return true  // continue
      }
      return body(occurrence)
    }
  }

  public func symbolProvider(for sourceFilePath: String) -> SymbolProviderKind? {
    return index.symbolProvider(for: sourceFilePath)
  }

  public func symbols(inFilePath path: String) -> [Symbol] {
    guard self.hasUpToDateUnit(for: URL(fileURLWithPath: path, isDirectory: false)) else {
      return []
    }
    return index.symbols(inFilePath: path)
  }

  /// Returns all unit test symbol in unit files that reference one of the main files in `mainFilePaths`.
  public func unitTests(referencedByMainFiles mainFilePaths: [String]) -> [SymbolOccurrence] {
    return index.unitTests(referencedByMainFiles: mainFilePaths).filter { checker.isUpToDate($0.location) }
  }

  /// Returns all unit test symbols in the index.
  public func unitTests() -> [SymbolOccurrence] {
    return index.unitTests().filter { checker.isUpToDate($0.location) }
  }

  /// Return `true` if a unit file has been indexed for the given file path after its last modification date.
  ///
  /// This means that at least a single build configuration of this file has been indexed since its last modification.
  public func hasUpToDateUnit(for url: URL) -> Bool {
    return checker.indexHasUpToDateUnit(for: url, index: index)
  }

  /// Returns true if the file at the given URL has a different content in the document manager than on-disk. This is
  /// the case if the user made edits to the file but didn't save them yet.
  ///
  /// - Important: This must only be called on a `CheckedIndex` with a `checkLevel` of `inMemoryModifiedFiles`
  public func fileHasInMemoryModifications(_ url: URL) -> Bool {
    return checker.fileHasInMemoryModifications(url)
  }
}

/// A wrapper around `IndexStoreDB` that allows the retrieval of a `CheckedIndex` with a specified check level or the
/// access of the underlying `IndexStoreDB`. This makes sure that accesses to the raw `IndexStoreDB` are explicit (by
/// calling `underlyingIndexStoreDB`) and we don't accidentally call into the `IndexStoreDB` when we wanted a
/// `CheckedIndex`.
public struct UncheckedIndex {
  public let underlyingIndexStoreDB: IndexStoreDB

  public init?(_ index: IndexStoreDB?) {
    guard let index else {
      return nil
    }
    self.underlyingIndexStoreDB = index
  }

  public func checked(for checkLevel: IndexCheckLevel) -> CheckedIndex {
    return CheckedIndex(index: underlyingIndexStoreDB, checkLevel: checkLevel)
  }
}

/// Helper class to check if symbols from the index are up-to-date or if the source file has been modified after it was
/// indexed. Modifications include both changes to the file on disk as well as modifications to the file that have not
/// been saved to disk (ie. changes that only live in `DocumentManager`).
///
/// The checker caches mod dates of source files. It should thus not be long lived. Its intended lifespan is the
/// evaluation of a single request.
private struct IndexOutOfDateChecker {
  private let checkLevel: IndexCheckLevel

  /// The last modification time of a file. Can also represent the fact that the file does not exist.
  private enum ModificationTime {
    case fileDoesNotExist
    case date(Date)
  }

  private enum Error: Swift.Error, CustomStringConvertible {
    case fileAttributesDontHaveModificationDate

    var description: String {
      switch self {
      case .fileAttributesDontHaveModificationDate:
        return "File attributes don't contain a modification date"
      }
    }
  }

  /// Caches whether a file URL has modifications in `documentManager` that haven't been saved to disk yet.
  private var fileHasInMemoryModificationsCache: [URL: Bool] = [:]

  /// File URLs to modification times that have already been computed.
  private var modTimeCache: [URL: ModificationTime] = [:]

  /// File URLs to whether they exist on the file system
  private var fileExistsCache: [URL: Bool] = [:]

  init(checkLevel: IndexCheckLevel) {
    self.checkLevel = checkLevel
  }

  // MARK: - Public interface

  /// Returns `true` if the source file for the given symbol location exists and has not been modified after it has been
  /// indexed.
  mutating func isUpToDate(_ symbolLocation: SymbolLocation) -> Bool {
    let url = URL(fileURLWithPath: symbolLocation.path, isDirectory: false)
    switch checkLevel {
    case .inMemoryModifiedFiles(let documentManager):
      if fileHasInMemoryModifications(url, documentManager: documentManager) {
        return false
      }
      fallthrough
    case .modifiedFiles:
      do {
        let sourceFileModificationDate = try modificationDate(of: url)
        switch sourceFileModificationDate {
        case .fileDoesNotExist:
          return false
        case .date(let sourceFileModificationDate):
          return sourceFileModificationDate <= symbolLocation.timestamp
        }
      } catch {
        logger.fault("Unable to determine if SymbolLocation is up-to-date: \(error.forLogging)")
        return true
      }
    case .deletedFiles:
      return fileExists(at: url)
    }
  }

  /// Return `true` if a unit file has been indexed for the given file path after its last modification date.
  ///
  /// This means that at least a single build configuration of this file has been indexed since its last modification.
  mutating func indexHasUpToDateUnit(for filePath: URL, index: IndexStoreDB) -> Bool {
    switch checkLevel {
    case .inMemoryModifiedFiles(let documentManager):
      if fileHasInMemoryModifications(filePath, documentManager: documentManager) {
        // If there are in-memory modifications to the file, we can't have an up-to-date unit since we only index files
        // on disk.
        return false
      }
      // If there are no in-memory modifications check if there are on-disk modifications.
      fallthrough
    case .modifiedFiles:
      guard let lastUnitDate = index.dateOfLatestUnitFor(filePath: filePath.path) else {
        return false
      }
      do {
        let sourceModificationDate = try modificationDate(of: filePath)
        switch sourceModificationDate {
        case .fileDoesNotExist:
          return false
        case .date(let sourceModificationDate):
          return sourceModificationDate <= lastUnitDate
        }
      } catch {
        logger.fault("Unable to determine if source file has up-to-date unit: \(error.forLogging)")
        return true
      }
    case .deletedFiles:
      // If we are asked if the index has an up-to-date unit for a source file, we can reasonably assume that this
      // source file exists (otherwise, why are we doing the query at all). Thus, there's nothing to check here.
      return true
    }
  }

  // MARK: - Cached check primitives

  /// `documentManager` must always be the same between calls to `hasFileInMemoryModifications` since it is not part of
  /// the cache key. This is fine because we always assume the `documentManager` to come from the associated value of
  /// `CheckLevel.imMemoryModifiedFiles`, which is constant.
  private mutating func fileHasInMemoryModifications(_ url: URL, documentManager: DocumentManager) -> Bool {
    if let cached = fileHasInMemoryModificationsCache[url] {
      return cached
    }
    let hasInMemoryModifications = documentManager.fileHasInMemoryModifications(url)
    fileHasInMemoryModificationsCache[url] = hasInMemoryModifications
    return hasInMemoryModifications
  }

  /// Returns true if the file at the given URL has a different content in the document manager than on-disk. This is
  /// the case if the user made edits to the file but didn't save them yet.
  ///
  /// - Important: This must only be called on an `IndexOutOfDateChecker` with a `checkLevel` of `inMemoryModifiedFiles`
  mutating func fileHasInMemoryModifications(_ url: URL) -> Bool {
    switch checkLevel {
    case .inMemoryModifiedFiles(let documentManager):
      return fileHasInMemoryModifications(url, documentManager: documentManager)
    case .modifiedFiles, .deletedFiles:
      logger.fault(
        "fileHasInMemoryModifications(at:) must only be called on an `IndexOutOfDateChecker` with check level .inMemoryModifiedFiles"
      )
      return false
    }
  }

  private func modificationDateUncached(of url: URL) throws -> ModificationTime {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
      guard let modificationDate = attributes[FileAttributeKey.modificationDate] as? Date else {
        throw Error.fileAttributesDontHaveModificationDate
      }
      return .date(modificationDate)
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
      return .fileDoesNotExist
    }
  }

  private mutating func modificationDate(of url: URL) throws -> ModificationTime {
    if let cached = modTimeCache[url] {
      return cached
    }
    let modTime = try modificationDateUncached(of: url)
    modTimeCache[url] = modTime
    return modTime
  }

  private mutating func fileExists(at url: URL) -> Bool {
    if let cached = fileExistsCache[url] {
      return cached
    }
    let fileExists = FileManager.default.fileExists(atPath: url.path)
    fileExistsCache[url] = fileExists
    return fileExists
  }
}

extension DocumentManager {
  /// Returns true if the file at the given URL has a different content in the document manager than on-disk. This is
  /// the case if the user made edits to the file but didn't save them yet.
  func fileHasInMemoryModifications(_ url: URL) -> Bool {
    guard let document = try? latestSnapshot(DocumentURI(url)) else {
      return false
    }

    guard let onDiskFileContents = try? String(contentsOf: url, encoding: .utf8) else {
      // If we can't read the file on disk, it can't match any on-disk state, so it's in-memory state
      return true
    }
    return onDiskFileContents != document.lineTable.content
  }
}
