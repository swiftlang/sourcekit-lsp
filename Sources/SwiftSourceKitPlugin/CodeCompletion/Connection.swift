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

import CompletionScoring
import Csourcekitd
import Foundation
import SKLogging
import SKUtilities
import SourceKitD
import SwiftExtensions

extension PopularityIndex.Scope {
  init(string name: String) {
    if let dotIndex = name.firstIndex(of: ".") {
      self.init(
        container: String(name[name.index(after: dotIndex)...]),
        module: String(name[..<dotIndex])
      )
    } else {
      self.init(container: nil, module: name)
    }
  }
}

/// Execute the given block on a thread with the given stack size and wait for that thread to finish.
fileprivate func withStackSize<T>(_ stackSize: Int, execute block: @Sendable @escaping () -> T) -> T {
  var result: T! = nil
  nonisolated(unsafe) let workItem = DispatchWorkItem(block: {
    result = block()
  })
  let thread = Thread {
    workItem.perform()
  }
  thread.stackSize = stackSize
  thread.start()
  workItem.wait()
  return result!
}

final class Connection {
  enum Error: SourceKitPluginError, CustomStringConvertible {
    case openingFileFailed(path: String)
    /// An error that occurred inside swiftIDE while performing completion.
    case swiftIDEError(String)
    case cancelled

    var description: String {
      switch self {
      case .openingFileFailed(path: let path):
        return "Could not open file '\(path)'"
      case .swiftIDEError(let message):
        return message
      case .cancelled:
        return "Request cancelled"
      }
    }

    func response(sourcekitd: any SourceKitD) -> SKDResponse {
      switch self {
      case .openingFileFailed, .swiftIDEError:
        return SKDResponse(error: .failed, description: description, sourcekitd: sourcekitd)
      case .cancelled:
        return SKDResponse(error: .cancelled, description: "Request cancelled", sourcekitd: sourcekitd)
      }
    }
  }

  fileprivate let logger = Logger(subsystem: "org.swift.sourcekit.service-plugin", category: "Connection")

  private let impl: swiftide_api_connection_t
  let sourcekitd: SourceKitD

  /// The list of documents that are open in SourceKitD. The key is the file's path on disk or a pseudo-path that
  /// uniquely identifies the document if it doesn't exist on disk.
  private var documents: [String: Document] = [:]

  /// Information to construct `PopularityIndex`.
  private var scopedPopularityDataPath: String?
  private var popularModules: [String]?
  private var notoriousModules: [String]?

  /// Cached data read from `scopedPopularityDataPath`.
  private var _scopedPopularityData: LazyValue<[PopularityIndex.Scope: [String: Double]]?> = .uninitialized

  /// Cached index.
  private var _popularityIndex: LazyValue<PopularityIndex?> = .uninitialized

  /// Deprecated.
  /// NOTE: `PopularityTable` was replaced with `PopularityIndex`. We keep this
  /// until all clients migrates to `PopularityIndex`.
  private var onlyPopularCompletions: PopularityTable = .init()

  /// Recent completions that were accepted by the client.
  private var recentCompletions: [String] = []

  /// The stack size that should be used for all operations that end up invoking the type checker.
  private let semanticStackSize = 8 << 20  // 8 MB.

  init(opaqueIDEInspectionInstance: UnsafeMutableRawPointer?, sourcekitd: SourceKitD) {
    self.sourcekitd = sourcekitd
    impl = sourcekitd.ideApi.connection_create_with_inspection_instance(opaqueIDEInspectionInstance)
  }

  deinit {
    sourcekitd.ideApi.connection_dispose(impl)
  }

  //// A function that can be called to cancel a request with a request.
  ///
  /// This is not a member function on `Connection` so that `CompletionProvider` can store
  /// this closure in a member and call it even while the `CompletionProvider` actor is busy
  /// fulfilling a completion request and thus can't access `connection`.
  var cancellationFunc: @Sendable (RequestHandle) -> Void {
    nonisolated(unsafe) let impl = self.impl
    return { [sourcekitd] handle in
      sourcekitd.ideApi.cancel_request(impl, handle.handle)
    }
  }

  func openDocument(path: String, contents: String, compilerArguments: [String]? = nil) {
    if documents[path] != nil {
      logger.error("Document at '\(path)' is already open")
    }
    documents[path] = Document(contents: contents, compilerArguments: compilerArguments)
    sourcekitd.ideApi.set_file_contents(impl, path, contents)
  }

  func editDocument(path: String, atUTF8Offset offset: Int, length: Int, newText: String) {
    guard let document = documents[path] else {
      logger.error("Document at '\(path)' is not open")
      return
    }

    document.lineTable.replace(utf8Offset: offset, length: length, with: newText)

    sourcekitd.ideApi.set_file_contents(impl, path, document.lineTable.content)
  }

  func editDocument(path: String, edit: TextEdit) {
    guard let document = documents[path] else {
      logger.error("Document at '\(path)' is not open")
      return
    }

    document.lineTable.replace(
      fromLine: edit.range.lowerBound.line - 1,
      utf8Offset: edit.range.lowerBound.utf8Column - 1,
      toLine: edit.range.upperBound.line - 1,
      utf8Offset: edit.range.upperBound.utf8Column - 1,
      with: edit.newText
    )

    sourcekitd.ideApi.set_file_contents(impl, path, document.lineTable.content)
  }

  func closeDocument(path: String) {
    if documents[path] == nil {
      logger.error("Document at '\(path)' was not open")
    }
    documents[path] = nil
    sourcekitd.ideApi.set_file_contents(impl, path, nil)
  }

  func complete(
    at loc: Location,
    arguments reqArgs: [String]? = nil,
    options: CompletionOptions,
    handle: swiftide_api_request_handle_t?
  ) throws -> CompletionSession {
    let offset: Int = try {
      if let lineTable = documents[loc.path]?.lineTable {
        return lineTable.utf8OffsetOf(line: loc.line - 1, utf8Column: loc.utf8Column - 1)
      } else {
        // FIXME: move line:column translation into C++ impl. so that we can avoid reading the file an extra time here.
        do {
          logger.log("Received code completion request for file that wasn't open. Reading file contents from disk.")
          let contents = try String(contentsOfFile: loc.path)
          let lineTable = LineTable(contents)
          return lineTable.utf8OffsetOf(line: loc.line - 1, utf8Column: loc.utf8Column - 1)
        } catch {
          throw Error.openingFileFailed(path: loc.path)
        }
      }
    }()

    let arguments = reqArgs ?? documents[loc.path]?.compilerArguments ?? []

    let result: swiftide_api_completion_response_t = withArrayOfCStrings(arguments) { cargs in
      let req = sourcekitd.ideApi.completion_request_create(loc.path, UInt32(offset), cargs, UInt32(cargs.count))
      defer { sourcekitd.ideApi.completion_request_dispose(req) }
      sourcekitd.ideApi.completion_request_set_annotate_result(req, options.annotateResults)
      sourcekitd.ideApi.completion_request_set_include_objectliterals(req, options.includeObjectLiterals);
      sourcekitd.ideApi.completion_request_set_add_inits_to_top_level(req, options.addInitsToTopLevel);
      sourcekitd.ideApi.completion_request_set_add_call_with_no_default_args(req, options.addCallWithNoDefaultArgs);

      do {
        let sourcekitd = self.sourcekitd
        nonisolated(unsafe) let impl = impl
        nonisolated(unsafe) let req = req
        nonisolated(unsafe) let handle = handle
        return withStackSize(semanticStackSize) {
          sourcekitd.ideApi.complete_cancellable(impl, req, handle)!
        }
      }
    }

    if sourcekitd.ideApi.completion_result_is_error(result) {
      let errorDescription = String(cString: sourcekitd.ideApi.completion_result_get_error_description(result)!)
      // Usually `CompletionSession` is responsible for disposing the result.
      // Since we don't form a `CompletionSession`, dispose of the result manually.
      sourcekitd.ideApi.completion_result_dispose(result)
      throw Error.swiftIDEError(errorDescription)
    } else if sourcekitd.ideApi.completion_result_is_cancelled(result) {
      sourcekitd.ideApi.completion_result_dispose(result)
      throw Error.cancelled
    }

    return CompletionSession(
      connection: self,
      location: loc,
      response: result,
      options: options
    )
  }

  func markCachedCompilerInstanceShouldBeInvalidated() {
    sourcekitd.ideApi.connection_mark_cached_compiler_instance_should_be_invalidated(impl, nil)
  }

  // MARK: 'PopularityIndex' APIs.

  func updatePopularityIndex(
    scopedPopularityDataPath: String,
    popularModules: [String],
    notoriousModules: [String]
  ) {

    // Clear the cache if necessary.
    // We don't check the content of the path assuming it's not changed.
    // For 'popular/notoriousModules', we expect around 200 elements.
    if scopedPopularityDataPath != self.scopedPopularityDataPath {
      self._popularityIndex = .uninitialized
      self._scopedPopularityData = .uninitialized
    } else if popularModules != self.popularModules || notoriousModules != self.notoriousModules {
      self._popularityIndex = .uninitialized
    }

    self.scopedPopularityDataPath = scopedPopularityDataPath
    self.popularModules = popularModules
    self.notoriousModules = notoriousModules
  }

  private var scopedPopularityData: [PopularityIndex.Scope: [String: Double]]? {
    _scopedPopularityData.cachedValueOrCompute {
      guard let jsonPath = self.scopedPopularityDataPath else {
        return nil
      }

      // A codable representation of `PopularityIndex.symbolPopularity`.
      struct ScopedSymbolPopularity: Codable {
        let values: [String]
        let scores: [Double]

        var table: [String: Double] {
          var map = [String: Double]()
          for (value, score) in zip(values, scores) {
            map[value] = score
          }
          return map
        }
      }

      do {
        let jsonURL = URL(fileURLWithPath: jsonPath)
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: jsonURL)
        let decoded = try decoder.decode([String: ScopedSymbolPopularity].self, from: data)
        var result = [PopularityIndex.Scope: [String: Double]]()
        for (rawScope, popularity) in decoded {
          let scope = PopularityIndex.Scope(string: rawScope)
          result[scope] = popularity.table
        }
        return result
      } catch {
        logger.error("Failed to read popularity data at '\(jsonPath)'")
        return nil
      }
    }
  }

  var popularityIndex: PopularityIndex? {
    _popularityIndex.cachedValueOrCompute {
      guard let scopedPopularityData, let popularModules, let notoriousModules else {
        return nil
      }
      return PopularityIndex(
        symbolReferencePercentages: scopedPopularityData,
        notoriousSymbols: /*unused*/ [],
        popularModules: popularModules,
        notoriousModules: notoriousModules
      )
    }
  }

  // MARK: 'PopularityTable' APIs (DEPRECATED).

  func updatePopularAPI(popularityTable: PopularityTable) {
    self.onlyPopularCompletions = popularityTable
  }

  func updateRecentCompletions(_ recent: [String]) {
    self.recentCompletions = recent
  }

  var popularityTable: PopularityTable {
    var result = onlyPopularCompletions
    result.add(popularSymbols: recentCompletions)
    return result
  }
}

private final class Document {
  var lineTable: LineTable
  var compilerArguments: [String]? = nil

  init(contents: String, compilerArguments: [String]? = nil) {
    self.lineTable = LineTable(contents)
    self.compilerArguments = compilerArguments
  }
}
