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

#if compiler(>=6)
import Foundation
@preconcurrency package import IndexStoreDB
package import LanguageServerProtocol
import SKLogging
import SwiftExtensions
#else
import Foundation
@preconcurrency import IndexStoreDB
import LanguageServerProtocol
import SKLogging
import SwiftExtensions
#endif

/// Essentially a `DocumentManager` from the `SourceKitLSP` module.
///
/// Protocol is needed because the `SemanticIndex` module is lower-level than the `SourceKitLSP` module.
package protocol InMemoryDocumentManager {
  /// Returns true if the file at the given URI has a different content in the document manager than on-disk. This is
  /// the case if the user made edits to the file but didn't save them yet.
  func fileHasInMemoryModifications(_ uri: DocumentURI) -> Bool
}

package enum IndexCheckLevel {
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
  case inMemoryModifiedFiles(InMemoryDocumentManager)
}

/// A wrapper around `IndexStoreDB` that checks if returned symbol occurrences are up-to-date with regard to a
/// `IndexCheckLevel`.
///
/// - SeeAlso: Comment on `IndexOutOfDateChecker`
package final class CheckedIndex {
  private var checker: IndexOutOfDateChecker
  private let index: IndexStoreDB

  /// Maps the USR of a symbol to its name and the name of all its containers, from outermost to innermost.
  ///
  /// It is important that we cache this because we might find a lot of symbols in the same container for eg. workspace
  /// symbols (eg. consider many symbols in the same C++ namespace). If we didn't cache this value, then we would need
  /// to perform a `primaryDefinitionOrDeclarationOccurrence` lookup for all of these containers, which is expensive.
  ///
  /// Since we don't expect `CheckedIndex` to be outlive a single request it is acceptable to cache these results
  /// without having any invalidation logic (similar to how we don't invalide results cached in
  /// `IndexOutOfDateChecker`).
  ///
  /// ### Examples
  /// If we have
  /// ```swift
  /// struct Foo {}
  /// ``` then
  /// `containerNamesCache[<usr of Foo>]` will be `["Foo"]`.
  ///
  /// If we have
  /// ```swift
  /// struct Bar {
  ///   struct Foo {}
  /// }
  /// ```, then
  /// `containerNamesCache[<usr of Foo>]` will be `["Bar", "Foo"]`.
  private var containerNamesCache: [String: [String]] = [:]

  fileprivate init(index: IndexStoreDB, checkLevel: IndexCheckLevel) {
    self.index = index
    self.checker = IndexOutOfDateChecker(checkLevel: checkLevel)
  }

  package var unchecked: UncheckedIndex {
    return UncheckedIndex(index)
  }

  @discardableResult
  package func forEachSymbolOccurrence(
    byUSR usr: String,
    roles: SymbolRole,
    _ body: (SymbolOccurrence) -> Bool
  ) -> Bool {
    index.forEachSymbolOccurrence(byUSR: usr, roles: roles) { occurrence in
      guard self.checker.isUpToDate(occurrence.location) else {
        return true  // continue
      }
      return body(occurrence)
    }
  }

  package func occurrences(ofUSR usr: String, roles: SymbolRole) -> [SymbolOccurrence] {
    return index.occurrences(ofUSR: usr, roles: roles).filter { checker.isUpToDate($0.location) }
  }

  package func occurrences(relatedToUSR usr: String, roles: SymbolRole) -> [SymbolOccurrence] {
    return index.occurrences(relatedToUSR: usr, roles: roles).filter { checker.isUpToDate($0.location) }
  }

  @discardableResult package func forEachCanonicalSymbolOccurrence(
    containing pattern: String,
    anchorStart: Bool,
    anchorEnd: Bool,
    subsequence: Bool,
    ignoreCase: Bool,
    body: (SymbolOccurrence) -> Bool
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

  @discardableResult package func forEachCanonicalSymbolOccurrence(
    byName name: String,
    body: (SymbolOccurrence) -> Bool
  ) -> Bool {
    index.forEachCanonicalSymbolOccurrence(byName: name) { occurrence in
      guard self.checker.isUpToDate(occurrence.location) else {
        return true  // continue
      }
      return body(occurrence)
    }
  }

  package func symbols(inFilePath path: String) -> [Symbol] {
    guard self.hasUpToDateUnit(for: DocumentURI(filePath: path, isDirectory: false)) else {
      return []
    }
    return index.symbols(inFilePath: path)
  }

  /// Returns all unit test symbol in unit files that reference one of the main files in `mainFilePaths`.
  package func unitTests(referencedByMainFiles mainFilePaths: [String]) -> [SymbolOccurrence] {
    return index.unitTests(referencedByMainFiles: mainFilePaths).filter { checker.isUpToDate($0.location) }
  }

  /// Returns all the files that (transitively) include the header file at the given path.
  ///
  /// If `crossLanguage` is set to `true`, Swift files that import a header through a module will also be reported.
  package func mainFilesContainingFile(uri: DocumentURI, crossLanguage: Bool = false) -> [DocumentURI] {
    return index.mainFilesContainingFile(path: uri.pseudoPath, crossLanguage: crossLanguage).compactMap {
      let uri = DocumentURI(filePath: $0, isDirectory: false)
      guard checker.indexHasUpToDateUnit(for: uri, mainFile: nil, index: self.index) else {
        return nil
      }
      return uri
    }
  }

  /// Returns all unit test symbols in the index.
  package func unitTests() -> [SymbolOccurrence] {
    return index.unitTests().filter { checker.isUpToDate($0.location) }
  }

  /// Return `true` if a unit file has been indexed for the given file path after its last modification date.
  ///
  /// This means that at least a single build configuration of this file has been indexed since its last modification.
  ///
  /// If `mainFile` is passed, then `url` is a header file that won't have a unit associated with it. `mainFile` is
  /// assumed to be a file that imports `url`. To check that `url` has an up-to-date unit, check that the latest unit
  /// for `mainFile` is newer than the mtime of the header file at `url`.
  package func hasUpToDateUnit(for uri: DocumentURI, mainFile: DocumentURI? = nil) -> Bool {
    return checker.indexHasUpToDateUnit(for: uri, mainFile: mainFile, index: index)
  }

  /// Returns true if the file at the given URI has a different content in the document manager than on-disk. This is
  /// the case if the user made edits to the file but didn't save them yet.
  ///
  /// - Important: This must only be called on a `CheckedIndex` with a `checkLevel` of `inMemoryModifiedFiles`
  package func fileHasInMemoryModifications(_ uri: DocumentURI) -> Bool {
    return checker.fileHasInMemoryModifications(uri)
  }

  /// If there are any definition occurrences of the given USR, return these.
  /// Otherwise return declaration occurrences.
  package func definitionOrDeclarationOccurrences(ofUSR usr: String) -> [SymbolOccurrence] {
    let definitions = occurrences(ofUSR: usr, roles: [.definition])
    if !definitions.isEmpty {
      return definitions
    }
    return occurrences(ofUSR: usr, roles: [.declaration])
  }

  /// Find a `SymbolOccurrence` that is considered the primary definition of the symbol with the given USR.
  ///
  /// If the USR has an ambiguous definition, the most important role of this function is to deterministically return
  /// the same result every time.
  package func primaryDefinitionOrDeclarationOccurrence(ofUSR usr: String) -> SymbolOccurrence? {
    let result = definitionOrDeclarationOccurrences(ofUSR: usr).sorted().first
    if result == nil {
      logger.error("Failed to find definition of \(usr) in index")
    }
    return result
  }

  /// The names of all containers the symbol is contained in, from outermost to innermost.
  ///
  /// ### Examples
  /// In the following, the container names of `test` are `["Foo"]`.
  /// ```swift
  /// struct Foo {
  ///   func test() {}
  /// }
  /// ```
  ///
  /// In the following, the container names of `test` are `["Bar", "Foo"]`.
  /// ```swift
  /// struct Bar {
  ///   struct Foo {
  ///     func test() {}
  ///   }
  /// }
  /// ```
  package func containerNames(of symbol: SymbolOccurrence) -> [String] {
    // The container name of accessors is the container of the surrounding variable.
    let accessorOf = symbol.relations.filter { $0.roles.contains(.accessorOf) }
    if let primaryVariable = accessorOf.sorted().first {
      if accessorOf.count > 1 {
        logger.fault("Expected an occurrence to an accessor of at most one symbol, not multiple")
      }
      if let primaryVariable = primaryDefinitionOrDeclarationOccurrence(ofUSR: primaryVariable.symbol.usr) {
        return containerNames(of: primaryVariable)
      }
    }

    let containers = symbol.relations.filter { $0.roles.contains(.childOf) }
    if containers.count > 1 {
      logger.fault("Expected an occurrence to a child of at most one symbol, not multiple")
    }
    let container = containers.filter {
      switch $0.symbol.kind {
      case .module, .namespace, .enum, .struct, .class, .protocol, .extension, .union:
        return true
      case .unknown, .namespaceAlias, .macro, .typealias, .function, .variable, .field, .enumConstant,
        .instanceMethod, .classMethod, .staticMethod, .instanceProperty, .classProperty, .staticProperty, .constructor,
        .destructor, .conversionFunction, .parameter, .using, .concept, .commentTag:
        return false
      }
    }.sorted().first

    guard var containerSymbol = container?.symbol else {
      return []
    }
    if let cached = containerNamesCache[containerSymbol.usr] {
      return cached
    }

    if containerSymbol.kind == .extension,
      let extendedSymbol = self.occurrences(relatedToUSR: containerSymbol.usr, roles: .extendedBy).first?.symbol
    {
      containerSymbol = extendedSymbol
    }
    let result: [String]

    // Use `forEachSymbolOccurrence` instead of `primaryDefinitionOrDeclarationOccurrence` to get a symbol occurrence
    // for the container because it can be significantly faster: Eg. when searching for a C++ namespace (such as `llvm`),
    // it may be declared in many files. Finding the canonical definition means that we would need to scan through all
    // of these files. But we expect all all of these declarations to have the same parent container names and we don't
    // care about locations here.
    var containerDefinition: SymbolOccurrence?
    forEachSymbolOccurrence(byUSR: containerSymbol.usr, roles: [.definition, .declaration]) { occurrence in
      containerDefinition = occurrence
      return false  // stop iteration
    }
    if let containerDefinition {
      result = self.containerNames(of: containerDefinition) + [containerSymbol.name]
    } else {
      result = [containerSymbol.name]
    }
    containerNamesCache[containerSymbol.usr] = result
    return result
  }
}

/// A wrapper around `IndexStoreDB` that allows the retrieval of a `CheckedIndex` with a specified check level or the
/// access of the underlying `IndexStoreDB`. This makes sure that accesses to the raw `IndexStoreDB` are explicit (by
/// calling `underlyingIndexStoreDB`) and we don't accidentally call into the `IndexStoreDB` when we wanted a
/// `CheckedIndex`.
package struct UncheckedIndex: Sendable {
  package let underlyingIndexStoreDB: IndexStoreDB

  package init?(_ index: IndexStoreDB?) {
    guard let index else {
      return nil
    }
    self.underlyingIndexStoreDB = index
  }

  package init(_ index: IndexStoreDB) {
    self.underlyingIndexStoreDB = index
  }

  package func checked(for checkLevel: IndexCheckLevel) -> CheckedIndex {
    return CheckedIndex(index: underlyingIndexStoreDB, checkLevel: checkLevel)
  }

  /// Wait for IndexStoreDB to be updated based on new unit files written to disk.
  package func pollForUnitChangesAndWait() {
    self.underlyingIndexStoreDB.pollForUnitChangesAndWait()
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

  /// Caches whether a document has modifications in `documentManager` that haven't been saved to disk yet.
  private var fileHasInMemoryModificationsCache: [DocumentURI: Bool] = [:]

  /// Document URIs to modification times that have already been computed.
  private var modTimeCache: [DocumentURI: ModificationTime] = [:]

  /// Document URIs to whether they exist on the file system
  private var fileExistsCache: [DocumentURI: Bool] = [:]

  init(checkLevel: IndexCheckLevel) {
    self.checkLevel = checkLevel
  }

  // MARK: - Public interface

  /// Returns `true` if the source file for the given symbol location exists and has not been modified after it has been
  /// indexed.
  mutating func isUpToDate(_ symbolLocation: SymbolLocation) -> Bool {
    let uri = DocumentURI(filePath: symbolLocation.path, isDirectory: false)
    switch checkLevel {
    case .inMemoryModifiedFiles(let documentManager):
      if fileHasInMemoryModifications(uri, documentManager: documentManager) {
        return false
      }
      fallthrough
    case .modifiedFiles:
      do {
        let sourceFileModificationDate = try modificationDate(of: uri)
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
      return fileExists(at: uri)
    }
  }

  /// Return `true` if a unit file has been indexed for the given file path after its last modification date.
  ///
  /// This means that at least a single build configuration of this file has been indexed since its last modification.
  ///
  /// If `mainFile` is passed, then `filePath` is a header file that won't have a unit associated with it. `mainFile` is
  /// assumed to be a file that imports `url`. To check that `url` has an up-to-date unit, check that the latest unit
  /// for `mainFile` is newer than the mtime of the header file at `url`.
  mutating func indexHasUpToDateUnit(for filePath: DocumentURI, mainFile: DocumentURI?, index: IndexStoreDB) -> Bool {
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
      guard
        let filePathStr = orLog("Realpath for up-to-date", { try (mainFile ?? filePath).fileURL?.realpath.filePath }),
        let lastUnitDate = index.dateOfLatestUnitFor(filePath: filePathStr)
      else {
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
  private mutating func fileHasInMemoryModifications(
    _ uri: DocumentURI,
    documentManager: InMemoryDocumentManager
  ) -> Bool {
    if let cached = fileHasInMemoryModificationsCache[uri] {
      return cached
    }
    let hasInMemoryModifications = documentManager.fileHasInMemoryModifications(uri)
    fileHasInMemoryModificationsCache[uri] = hasInMemoryModifications
    return hasInMemoryModifications
  }

  /// Returns true if the file at the given URI has a different content in the document manager than on-disk. This is
  /// the case if the user made edits to the file but didn't save them yet.
  ///
  /// - Important: This must only be called on an `IndexOutOfDateChecker` with a `checkLevel` of `inMemoryModifiedFiles`
  mutating func fileHasInMemoryModifications(_ uri: DocumentURI) -> Bool {
    switch checkLevel {
    case .inMemoryModifiedFiles(let documentManager):
      return fileHasInMemoryModifications(uri, documentManager: documentManager)
    case .modifiedFiles, .deletedFiles:
      logger.fault(
        "fileHasInMemoryModifications(at:) must only be called on an `IndexOutOfDateChecker` with check level .inMemoryModifiedFiles"
      )
      return false
    }
  }

  private static func modificationDate(atPath path: String) throws -> Date {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard let modificationDate = attributes[FileAttributeKey.modificationDate] as? Date else {
      throw Error.fileAttributesDontHaveModificationDate
    }
    return modificationDate
  }

  private func modificationDateUncached(of uri: DocumentURI) throws -> ModificationTime {
    do {
      guard var fileURL = uri.fileURL else {
        return .fileDoesNotExist
      }
      var modificationDate = try Self.modificationDate(atPath: fileURL.filePath)

      // Get the maximum mtime in the symlink chain as the modification date of the URI. That way if either the symlink
      // is changed to point to a different file or if the underlying file is modified, the modification time is
      // updated.
      while let relativeSymlinkDestination = try? FileManager.default.destinationOfSymbolicLink(
        atPath: fileURL.filePath
      ),
        let symlinkDestination = URL(string: relativeSymlinkDestination, relativeTo: fileURL)
      {
        fileURL = symlinkDestination
        modificationDate = max(modificationDate, try Self.modificationDate(atPath: fileURL.filePath))
      }

      return .date(modificationDate)
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
      return .fileDoesNotExist
    }
  }

  private mutating func modificationDate(of uri: DocumentURI) throws -> ModificationTime {
    if let cached = modTimeCache[uri] {
      return cached
    }
    let modTime = try modificationDateUncached(of: uri)
    modTimeCache[uri] = modTime
    return modTime
  }

  private mutating func fileExists(at uri: DocumentURI) -> Bool {
    if let cached = fileExistsCache[uri] {
      return cached
    }
    let fileExists =
      if let fileUrl = uri.fileURL {
        FileManager.default.fileExists(at: fileUrl)
      } else {
        false
      }
    fileExistsCache[uri] = fileExists
    return fileExists
  }
}
