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

import Dispatch
import LSPLogging
import LanguageServerProtocol
import SourceKitD

/// Represents a code-completion session for a given source location that can be efficiently
/// re-filtered by calling `update()`.
///
/// The first call to `update()` opens the session with sourcekitd, which computes the initial
/// completions. Subsequent calls to `update()` will re-filter the original completions. Finally,
/// before creating a new completion session, you must call `close()`. It is an error to create a
/// new completion session with the same source location before closing the original session.
///
/// At the sourcekitd level, this uses `codecomplete.open`, `codecomplete.update` and
/// `codecomplete.close` requests.
actor CodeCompletionSession {
  private unowned let server: SwiftLanguageServer
  private let snapshot: DocumentSnapshot
  let utf8StartOffset: Int
  private let position: Position
  private let compileCommand: SwiftCompileCommand?
  private var state: State = .closed

  private enum State {
    case closed
    case open
  }

  nonisolated var uri: DocumentURI { snapshot.uri }

  init(
    server: SwiftLanguageServer,
    snapshot: DocumentSnapshot,
    utf8Offset: Int,
    position: Position,
    compileCommand: SwiftCompileCommand?
  ) {
    self.server = server
    self.snapshot = snapshot
    self.utf8StartOffset = utf8Offset
    self.position = position
    self.compileCommand = compileCommand
  }

  /// Retrieve completions for the given `filterText`, opening or updating the session.
  ///
  /// - parameters:
  ///   - filterText: The text to use for fuzzy matching the results.
  ///   - position: The position at the end of the existing text (typically right after the end of
  ///               `filterText`), which determines the end of the `TextEdit` replacement range
  ///               in the resulting completions.
  ///   - snapshot: The current snapshot that the `TextEdit` replacement in results will be in.
  ///   - options: The completion options, such as the maximum number of results.
  func update(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions
  ) async throws -> CompletionList {
    switch self.state {
    case .closed:
      self.state = .open
      return try await self.open(filterText: filterText, position: position, in: snapshot, options: options)
    case .open:
      return try await self.updateImpl(filterText: filterText, position: position, in: snapshot, options: options)
    }
  }

  private func open(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions
  ) async throws -> CompletionList {
    log("\(Self.self) Open: \(self) filter=\(filterText)")
    guard snapshot.version == self.snapshot.version else {
      throw ResponseError(code: .invalidRequest, message: "open must use the original snapshot")
    }

    let req = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    req[keys.request] = server.sourcekitd.requests.codecomplete_open
    req[keys.offset] = utf8StartOffset
    req[keys.name] = uri.pseudoPath
    req[keys.sourcefile] = uri.pseudoPath
    req[keys.sourcetext] = snapshot.text
    req[keys.codecomplete_options] = optionsDictionary(filterText: filterText, options: options)
    if let compileCommand = compileCommand {
      req[keys.compilerargs] = compileCommand.compilerArgs
    }

    let dict = try await server.sourcekitd.send(req)

    guard let completions: SKDResponseArray = dict[keys.results] else {
      return CompletionList(isIncomplete: false, items: [])
    }

    try Task.checkCancellation()

    return self.server.completionsFromSKDResponse(
      completions,
      in: snapshot,
      completionPos: self.position,
      requestPosition: position,
      isIncomplete: true
    )
  }

  private func updateImpl(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions
  ) async throws -> CompletionList {
    // FIXME: Assertion for prefix of snapshot matching what we started with.

    log("\(Self.self) Update: \(self) filter=\(filterText)")
    let req = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    req[keys.request] = server.sourcekitd.requests.codecomplete_update
    req[keys.offset] = utf8StartOffset
    req[keys.name] = uri.pseudoPath
    req[keys.codecomplete_options] = optionsDictionary(filterText: filterText, options: options)

    let dict = try await server.sourcekitd.send(req)
    guard let completions: SKDResponseArray = dict[keys.results] else {
      return CompletionList(isIncomplete: false, items: [])
    }

    return self.server.completionsFromSKDResponse(
      completions,
      in: snapshot,
      completionPos: self.position,
      requestPosition: position,
      isIncomplete: true
    )
  }

  private func optionsDictionary(
    filterText: String,
    options: SKCompletionOptions
  ) -> SKDRequestDictionary {
    let dict = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    // Sorting and priority options.
    dict[keys.codecomplete_hideunderscores] = 0
    dict[keys.codecomplete_hidelowpriority] = 0
    dict[keys.codecomplete_hidebyname] = 0
    dict[keys.codecomplete_addinneroperators] = 0
    dict[keys.codecomplete_callpatternheuristics] = 0
    dict[keys.codecomplete_showtopnonliteralresults] = 0
    // Filtering options.
    dict[keys.codecomplete_filtertext] = filterText
    if let maxResults = options.maxResults {
      dict[keys.codecomplete_requestlimit] = maxResults
    }
    return dict
  }

  private func sendClose(_ server: SwiftLanguageServer) {
    let req = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    req[keys.request] = server.sourcekitd.requests.codecomplete_close
    req[keys.offset] = self.utf8StartOffset
    req[keys.name] = self.snapshot.uri.pseudoPath
    log("\(Self.self) Closing: \(self)")
    _ = try? server.sourcekitd.sendSync(req)
  }

  func close() async {
    // Temporary back-reference to server to keep it alive during close().
    let server = self.server

    switch self.state {
    case .closed:
      // Already closed, nothing to do.
      break
    case .open:
      self.sendClose(server)
      self.state = .closed
    }
  }
}

extension CodeCompletionSession: CustomStringConvertible {
  nonisolated var description: String {
    "\(uri.pseudoPath):\(position)"
  }
}
