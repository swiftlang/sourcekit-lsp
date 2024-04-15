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

/// Helper class to check if symbols from the index are up-to-date or if the source file has been modified after it was
/// indexed. Modifications include both changes to the file on disk as well as modifications to the file that have not
/// been saved to disk (ie. changes that only live in `DocumentManager`).
///
/// The checker caches mod dates of source files. It should thus not be long lived. Its intended lifespan is the
/// evaluation of a single request.
struct IndexOutOfDateChecker {
  /// The `DocumentManager` that holds the in-memory file contents. We consider the index out-of-date for all files that
  /// have in-memory changes.
  private let documentManager: DocumentManager

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

  /// File URLs to modification times that have already been computed.
  private var modTimeCache: [URL: ModificationTime] = [:]

  /// Caches whether a file URL has modifications in `documentManager` that haven't been saved to disk yet.
  private var hasFileInMemoryModificationsCache: [URL: Bool] = [:]

  init(documentManager: DocumentManager) {
    self.documentManager = documentManager
  }

  private func modificationDateUncached(of url: URL) throws -> ModificationTime {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
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

  private func hasFileInMemoryModificationsUncached(at url: URL) -> Bool {
    guard let document = try? documentManager.latestSnapshot(DocumentURI(url)) else {
      return false
    }

    guard let onDiskFileContents = try? String(contentsOf: url, encoding: .utf8) else {
      // If we can't read the file on disk, it's an in-memory document
      return true
    }
    return onDiskFileContents != document.lineTable.content
  }

  /// Returns `true` if the file has modified in-memory state, ie. if the version stored in the `DocumentManager` is
  /// different than the version on disk.
  public mutating func fileHasInMemoryModifications(_ url: URL) -> Bool {
    if let cached = hasFileInMemoryModificationsCache[url] {
      return cached
    }
    let hasInMemoryModifications = hasFileInMemoryModificationsUncached(at: url)
    hasFileInMemoryModificationsCache[url] = hasInMemoryModifications
    return hasInMemoryModifications
  }

  /// Returns `true` if the source file for the given symbol location exists and has not been modified after it has been
  /// indexed.
  mutating func isUpToDate(_ symbolLocation: SymbolLocation) -> Bool {
    if fileHasInMemoryModifications(URL(fileURLWithPath: symbolLocation.path)) {
      return false
    }
    do {
      let sourceFileModificationDate = try modificationDate(of: URL(fileURLWithPath: symbolLocation.path))
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
  }

  /// Return `true` if a unit file has been indexed for the given file path after its last modification date.
  ///
  /// This means that at least a single build configuration of this file has been indexed since its last modification.
  mutating func indexHasUpToDateUnit(for filePath: URL, index: IndexStoreDB) -> Bool {
    if fileHasInMemoryModifications(filePath) {
      return false
    }
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
  }
}
