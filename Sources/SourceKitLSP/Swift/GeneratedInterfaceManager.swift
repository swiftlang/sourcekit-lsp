//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import SKLogging
import SKUtilities
import SourceKitD
import SwiftExtensions

/// When information about a generated interface is requested, this opens the generated interface in sourcekitd and
/// caches the generated interface contents.
///
/// It keeps the generated interface open in sourcekitd until the corresponding reference document is closed in the
/// editor. Additionally, it also keeps a few recently requested interfaces cached. This way we don't need to recompute
/// the generated interface contents between the initial generated interface request to find a USR's position in the
/// interface until the editor actually opens the reference document.
actor GeneratedInterfaceManager {
  private struct OpenGeneratedInterfaceDocumentDetails {
    let url: GeneratedInterfaceDocumentURLData

    /// The contents of the generated interface.
    let snapshot: DocumentSnapshot

    /// The number of `GeneratedInterfaceManager` that are actively working with the sourcekitd document. If this value
    /// is 0, the generated interface may be closed in sourcekitd.
    ///
    /// Usually, this value is 1, while the reference document for this generated interface is open in the editor.
    var refCount: Int
  }

  private weak var swiftLanguageService: SwiftLanguageService?

  /// The number of generated interface documents that are not in editor but should still be cached.
  private let cacheSize = 2

  /// Details about the generated interfaces that are currently open in sourcekitd.
  ///
  /// Conceptually, this is a dictionary with `url` being the key. To prevent excessive memory usage we only keep
  ///  `cacheSize` entries with a ref count of 0 in the array. Older entries are at the end of the list, newer entries
  /// at the front.
  private var openInterfaces: [OpenGeneratedInterfaceDocumentDetails] = []

  init(swiftLanguageService: SwiftLanguageService) {
    self.swiftLanguageService = swiftLanguageService
  }

  /// If there are more than `cacheSize` entries in `openInterfaces` that have a ref count of 0, close the oldest ones.
  private func purgeCache() {
    var documentsToClose: [String] = []
    while openInterfaces.count(where: { $0.refCount == 0 }) > cacheSize,
      let indexToPurge = openInterfaces.lastIndex(where: { $0.refCount == 0 })
    {
      documentsToClose.append(openInterfaces[indexToPurge].url.sourcekitdDocumentName)
      openInterfaces.remove(at: indexToPurge)
    }
    if !documentsToClose.isEmpty, let swiftLanguageService {
      Task {
        let sourcekitd = swiftLanguageService.sourcekitd
        for documentToClose in documentsToClose {
          await orLog("Closing generated interface") {
            _ = try await swiftLanguageService.sendSourcekitdRequest(
              sourcekitd.dictionary([
                sourcekitd.keys.request: sourcekitd.requests.editorClose,
                sourcekitd.keys.name: documentToClose,
                sourcekitd.keys.cancelBuilds: 0,
              ]),
              fileContents: nil
            )
          }
        }
      }
    }
  }

  /// If we don't have the generated interface for the given `document` open in sourcekitd, open it, otherwise return
  /// its details from the cache.
  ///
  /// If `incrementingRefCount` is `true`, then the document manager will keep the generated interface open in
  /// sourcekitd, independent of the cache size. If `incrementingRefCount` is `true`, then `decrementRefCount` must be
  /// called to allow the document to be closed again.
  private func details(
    for document: GeneratedInterfaceDocumentURLData,
    incrementingRefCount: Bool
  ) async throws -> OpenGeneratedInterfaceDocumentDetails {
    func loadFromCache() -> OpenGeneratedInterfaceDocumentDetails? {
      guard let cachedIndex = openInterfaces.firstIndex(where: { $0.url == document }) else {
        return nil
      }
      if incrementingRefCount {
        openInterfaces[cachedIndex].refCount += 1
      }
      return openInterfaces[cachedIndex]

    }
    if let cached = loadFromCache() {
      return cached
    }

    guard let swiftLanguageService else {
      // `SwiftLanguageService` has been destructed. We are tearing down the language server. Nothing left to do.
      throw ResponseError.unknown("Connection to the editor closed")
    }

    let sourcekitd = swiftLanguageService.sourcekitd

    let keys = sourcekitd.keys
    let skreq = sourcekitd.dictionary([
      keys.request: sourcekitd.requests.editorOpenInterface,
      keys.moduleName: document.moduleName,
      keys.groupName: document.groupName,
      keys.name: document.sourcekitdDocumentName,
      keys.synthesizedExtension: 1,
      keys.compilerArgs: await swiftLanguageService.buildSettings(for: try document.uri, fallbackAfterTimeout: false)?
        .compilerArgs as [SKDRequestValue]?,
    ])

    let dict = try await swiftLanguageService.sendSourcekitdRequest(skreq, fileContents: nil)

    guard let contents: String = dict[keys.sourceText] else {
      throw ResponseError.unknown("sourcekitd response is missing sourceText")
    }

    if let cached = loadFromCache() {
      // Another request raced us to create the generated interface. Discard what we computed here and return the cached
      // value.
      await orLog("Closing generated interface created during race") {
        _ = try await swiftLanguageService.sendSourcekitdRequest(
          sourcekitd.dictionary([
            keys.request: sourcekitd.requests.editorClose,
            keys.name: document.sourcekitdDocumentName,
            keys.cancelBuilds: 0,
          ]),
          fileContents: nil
        )
      }
      return cached
    }

    let details = OpenGeneratedInterfaceDocumentDetails(
      url: document,
      snapshot: DocumentSnapshot(
        uri: try document.uri,
        language: .swift,
        version: 0,
        lineTable: LineTable(contents)
      ),
      refCount: incrementingRefCount ? 1 : 0
    )
    openInterfaces.insert(details, at: 0)
    purgeCache()
    return details
  }

  private func decrementRefCount(for document: GeneratedInterfaceDocumentURLData) {
    guard let cachedIndex = openInterfaces.firstIndex(where: { $0.url == document }) else {
      logger.fault(
        "Generated interface document for \(document.moduleName) is not open anymore. Unbalanced retain and releases?"
      )
      return
    }
    if openInterfaces[cachedIndex].refCount == 0 {
      logger.fault(
        "Generated interface document for \(document.moduleName) is already 0. Unbalanced retain and releases?"
      )
      return
    }
    openInterfaces[cachedIndex].refCount -= 1
    purgeCache()
  }

  func position(ofUsr usr: String, in document: GeneratedInterfaceDocumentURLData) async throws -> Position {
    guard let swiftLanguageService else {
      // `SwiftLanguageService` has been destructed. We are tearing down the language server. Nothing left to do.
      throw ResponseError.unknown("Connection to the editor closed")
    }

    let details = try await details(for: document, incrementingRefCount: true)
    defer {
      decrementRefCount(for: document)
    }

    let sourcekitd = swiftLanguageService.sourcekitd
    let keys = sourcekitd.keys
    let skreq = sourcekitd.dictionary([
      keys.request: sourcekitd.requests.editorFindUSR,
      keys.sourceFile: document.sourcekitdDocumentName,
      keys.usr: usr,
    ])

    let dict = try await swiftLanguageService.sendSourcekitdRequest(skreq, fileContents: details.snapshot.text)
    guard let offset: Int = dict[keys.offset] else {
      throw ResponseError.unknown("Missing key 'offset'")
    }
    return details.snapshot.positionOf(utf8Offset: offset)
  }

  func snapshot(of document: GeneratedInterfaceDocumentURLData) async throws -> DocumentSnapshot {
    return try await details(for: document, incrementingRefCount: false).snapshot
  }

  func open(document: GeneratedInterfaceDocumentURLData) async throws {
    _ = try await details(for: document, incrementingRefCount: true)
  }

  func close(document: GeneratedInterfaceDocumentURLData) async {
    decrementRefCount(for: document)
  }

  func reopen(interfacesWithBuildSettingsFrom buildSettingsFile: DocumentURI) async {
    for openInterface in openInterfaces {
      guard openInterface.url.buildSettingsFrom == buildSettingsFile else {
        continue
      }
      await orLog("Reopening generated interface") {
        // `MessageHandlingDependencyTracker` ensures that we don't handle a request for the generated interface while
        // it is being re-opened because `documentUpdate` and `documentRequest` use the `buildSettingsFile` to determine
        // their dependencies.
        await close(document: openInterface.url)
        openInterfaces.removeAll(where: { $0.url == openInterface.url })
        try await open(document: openInterface.url)
      }
    }
  }
}
