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

import LanguageServerProtocol
import LSPLogging
import SourceKitD
import Dispatch

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
class CodeCompletionSession {
  unowned let server: SwiftLanguageServer
  let queue: DispatchQueue
  let snapshot: DocumentSnapshot
  let utf8StartOffset: Int
  let position: Position
  let compileCommand: SwiftCompileCommand?
  var state: State = .closed

  enum State {
    case closed
    // FIXME: we should keep a real queue and cancel previous updates.
    case opening(DispatchGroup)
    case open
  }

  var uri: DocumentURI { snapshot.document.uri }

  init(
    server: SwiftLanguageServer,
    snapshot: DocumentSnapshot,
    utf8Offset: Int,
    position: Position,
    compileCommand: SwiftCompileCommand?)
  {
    self.server = server
    self.queue =
      DispatchQueue(label: "\(Self.self)-queue", qos: .userInitiated, target: server.queue)
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
  ///   - completion: Asynchronous callback to receive results or error response.
  func update(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions,
    completion: @escaping (LSPResult<CompletionList>) -> Void)
  {
    queue.async {
      switch self.state {
      case .closed:
        self._open(filterText: filterText, position: position, in: snapshot, options: options, completion: completion)
      case .opening(let group):
        group.notify(queue: self.queue) {
          switch self.state {
          case .closed, .opening(_):
            // Don't try again.
            completion(.failure(.serverCancelled))
          case .open:
            self._update(filterText: filterText, position: position, in: snapshot, options: options, completion: completion)
          }
        }
      case .open:
        self._update(filterText: filterText, position: position, in: snapshot, options: options, completion: completion)
      }
    }
  }

  func _open(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions,
    completion: @escaping  (LSPResult<CompletionList>) -> Void)
  {
    log("\(Self.self) Open: \(self) filter=\(filterText)")
    guard snapshot.version == self.snapshot.version else {
        completion(.failure(ResponseError(code: .invalidRequest, message: "open must use the original snapshot")))
        return
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

    let group = DispatchGroup()
    group.enter()

    state = .opening(group)

    let handle = server.sourcekitd.send(req, queue) { result in
      defer { group.leave() }

      guard let dict = result.success else {
        self.state = .closed
        return completion(.failure(ResponseError(result.failure!)))
      }
      if case .closed = self.state {
        return completion(.failure(.serverCancelled))
      }

      self.state = .open

      guard let completions: SKDResponseArray = dict[keys.results] else {
        return completion(.success(CompletionList(isIncomplete: false, items: [])))
      }

      let results = self.server.completionsFromSKDResponse(completions,
                                                           in: snapshot,
                                                           completionPos: self.position,
                                                           requestPosition: position,
                                                           isIncomplete: true)
      completion(.success(results))
    }

    // FIXME: cancellation
    _ = handle
  }

  func _update(
    filterText: String,
    position: Position,
    in snapshot: DocumentSnapshot,
    options: SKCompletionOptions,
    completion: @escaping  (LSPResult<CompletionList>) -> Void)
  {
    // FIXME: Assertion for prefix of snapshot matching what we started with.

    log("\(Self.self) Update: \(self) filter=\(filterText)")
    let req = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    req[keys.request] = server.sourcekitd.requests.codecomplete_update
    req[keys.offset] = utf8StartOffset
    req[keys.name] = uri.pseudoPath
    req[keys.codecomplete_options] = optionsDictionary(filterText: filterText, options: options)

    let handle = server.sourcekitd.send(req, queue) { result in
      guard let dict = result.success else {
        return completion(.failure(ResponseError(result.failure!)))
      }
      guard let completions: SKDResponseArray = dict[keys.results] else {
        return completion(.success(CompletionList(isIncomplete: false, items: [])))
      }

      completion(.success(self.server.completionsFromSKDResponse(completions, in: snapshot, completionPos: self.position, requestPosition: position, isIncomplete: true)))
    }

    // FIXME: cancellation
    _ = handle
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

  private func _sendClose(_ server: SwiftLanguageServer) {
    let req = SKDRequestDictionary(sourcekitd: server.sourcekitd)
    let keys = server.sourcekitd.keys
    req[keys.request] = server.sourcekitd.requests.codecomplete_close
    req[keys.offset] = self.utf8StartOffset
    req[keys.name] = self.snapshot.document.uri.pseudoPath
    log("\(Self.self) Closing: \(self)")
    _ = try? server.sourcekitd.sendSync(req)
  }

  func close() {
    // Temporary back-reference to server to keep it alive during close().
    let server = self.server

    queue.async {
      switch self.state {
        case .closed:
          // Already closed, nothing to do.
          break
        case .opening(let group):
          group.notify(queue: self.queue) {
            switch self.state {
            case .closed, .opening(_):
              // Don't try again.
              break
            case .open:
              self._sendClose(server)
              self.state = .closed
            }
          }
        case .open:
          self._sendClose(server)
          self.state = .closed
      }
    }
  }
}

extension CodeCompletionSession: CustomStringConvertible {
  var description: String {
    "\(uri.pseudoPath):\(position)"
  }
}
