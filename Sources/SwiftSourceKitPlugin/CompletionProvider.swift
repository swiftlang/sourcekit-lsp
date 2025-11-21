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
@_spi(SourceKitLSP) import SKLogging
import SourceKitD
import SwiftSourceKitPluginCommon

/// Parse a `[String: Popularity]` dictionary from an array of XPC dictionaries that looks as follows:
/// ```
/// [
///   {
///     "key.popularity.key": <some-module-name>,
///     "key.popularity.value.int.billion": <popularity-multiplied-by-one-billion>
///   },
///   ...
/// ]
/// ```
/// If a key occurs twice, we use the later value.
/// Returns `nil` if parsing failed because one of he entries didn't contain a key or value.
private func parsePopularityDict(_ data: SKDRequestArrayReader) -> [String: Popularity]? {
  var result: [String: Popularity] = [:]
  // swift-format-ignore: ReplaceForEachWithForLoop
  // Reference is to `SKDRequestArrayReader.forEach`, not `Array.forEach`.
  let iteratedAllEntries = data.forEach { (_, entry) -> Bool in
    // We can't deserialize double values in SourceKit requests at the moment.
    // We transfer the double value as an integer with 9 significant digits by multiplying it by 1 billion first.
    guard let key: String = entry[entry.sourcekitd.keys.popularityKey],
      let value: Int = entry[entry.sourcekitd.keys.popularityValueIntBillion]
    else {
      return false
    }
    result[key] = Popularity(scoreComponent: Double(value) / 1_000_000_000)
    return true
  }
  if !iteratedAllEntries {
    return nil
  }
  return result
}

extension PopularityTable {
  /// Create a PopularityTable from a serialized XPC form that looks as follows:
  /// ```
  /// {
  ///   "key.symbol_popularity": [ <see parsePopularityDict> ],
  ///   "key.module_popularity": [ <see parsePopularityDict> ],
  /// }
  /// ```
  /// Returns `nil` if the dictionary didn't match the expected format.
  init?(_ dict: SKDRequestDictionaryReader) {
    let keys = dict.sourcekitd.keys
    guard let symbolPopularityData: SKDRequestArrayReader = dict[keys.symbolPopularity],
      let symbolPopularity = parsePopularityDict(symbolPopularityData),
      let modulePopularityData: SKDRequestArrayReader = dict[keys.modulePopularity],
      let modulePopularity = parsePopularityDict(modulePopularityData)
    else {
      return nil
    }
    self.init(symbolPopularity: symbolPopularity, modulePopularity: modulePopularity)
  }
}

actor CompletionProvider {
  enum InvalidRequest: SourceKitPluginError {
    case missingKey(String)

    func response(sourcekitd: SourceKitD) -> SKDResponse {
      switch self {
      case .missingKey(let key):
        return SKDResponse(error: .invalid, description: "missing required key '\(key)'", sourcekitd: sourcekitd)
      }
    }
  }

  private let logger = Logger(subsystem: "org.swift.sourcekit.service-plugin", category: "CompletionProvider")

  private let connection: Connection

  /// See `Connection.cancellationFunc`
  private nonisolated let cancel: @Sendable (RequestHandle) -> Void

  /// The XPC custom buffer kind for `CompletionResultsArray`
  private let completionResultsBufferKind: UInt64

  /// The code completion session that's currently open.
  private var currentSession: CompletionSession? = nil

  init(
    completionResultsBufferKind: UInt64,
    opaqueIDEInspectionInstance: OpaqueIDEInspectionInstance? = nil,
    sourcekitd: SourceKitD
  ) {
    self.connection = Connection(
      opaqueIDEInspectionInstance: opaqueIDEInspectionInstance?.value,
      sourcekitd: sourcekitd
    )
    self.cancel = connection.cancellationFunc
    self.completionResultsBufferKind = completionResultsBufferKind
  }

  nonisolated func cancel(handle: RequestHandle) {
    self.cancel(handle)
  }

  func handleDocumentOpen(_ request: SKDRequestDictionaryReader) {
    let keys = request.sourcekitd.keys
    guard let path: String = request[keys.name] else {
      self.logger.error("error: dropping request editor.open: missing 'key.name'")
      return
    }
    let content: String
    if let text: String = request[keys.sourceText] {
      content = text
    } else if let file: String = request[keys.sourceFile] {
      logger.info("Document open request missing source text. Reading contents of '\(file)' from disk.")
      do {
        content = try String(contentsOfFile: file, encoding: .utf8)
      } catch {
        self.logger.error("error: dropping request editor.open: failed to read \(file): \(String(describing: error))")
        return
      }
    } else {
      self.logger.error("error: dropping request editor.open: missing 'key.sourcetext'")
      return
    }

    self.connection.openDocument(
      path: path,
      contents: content,
      compilerArguments: request[keys.compilerArgs]?.asStringArray
    )
  }

  func handleDocumentEdit(_ request: SKDRequestDictionaryReader) {
    let keys = request.sourcekitd.keys
    guard let path: String = request[keys.name] else {
      self.logger.error("error: dropping request editor.replacetext: missing 'key.name'")
      return
    }
    guard let offset: Int = request[keys.offset] else {
      self.logger.error("error: dropping request editor.replacetext: missing 'key.offset'")
      return
    }
    guard let length: Int = request[keys.length] else {
      self.logger.error("error: dropping request editor.replacetext: missing 'key.length'")
      return
    }
    guard let text: String = request[keys.sourceText] else {
      self.logger.error("error: dropping request editor.replacetext: missing 'key.sourcetext'")
      return
    }

    self.connection.editDocument(path: path, atUTF8Offset: offset, length: length, newText: text)
  }

  func handleDocumentClose(_ dict: SKDRequestDictionaryReader) {
    guard let path: String = dict[dict.sourcekitd.keys.name] else {
      self.logger.error("error: dropping request editor.close: missing 'key.name'")
      return
    }
    self.connection.closeDocument(path: path)
  }

  func handleCompleteOpen(
    _ request: SKDRequestDictionaryReader,
    handle: RequestHandle?
  ) throws -> SKDResponseDictionaryBuilder {
    let sourcekitd = request.sourcekitd
    let keys = sourcekitd.keys
    let location = try self.requestLocation(request)

    if self.currentSession != nil {
      logger.error("Opening a code completion session while previous is still open. Implicitly closing old session.")
      self.currentSession = nil
    }

    let options: SKDRequestDictionaryReader? = request[keys.codeCompleteOptions]
    let annotate = (options?[keys.annotatedDescription] as Int?) == 1
    let includeObjectLiterals = (options?[keys.includeObjectLiterals] as Int?) == 1
    let addInitsToTopLevel = (options?[keys.addInitsToTopLevel] as Int?) == 1
    let addCallWithNoDefaultArgs = (options?[keys.addCallWithNoDefaultArgs] as Int? == 1)
    let includeSemanticComponents = (options?[keys.includeSemanticComponents] as Int?) == 1

    if let recentCompletions: [String] = options?[keys.recentCompletions]?.asStringArray {
      self.connection.updateRecentCompletions(recentCompletions)
    }

    let session = try self.connection.complete(
      at: location,
      arguments: request[keys.compilerArgs]?.asStringArray,
      options: CompletionOptions(
        annotateResults: annotate,
        includeObjectLiterals: includeObjectLiterals,
        addInitsToTopLevel: addInitsToTopLevel,
        addCallWithNoDefaultArgs: addCallWithNoDefaultArgs,
        includeSemanticComponents: includeSemanticComponents
      ),
      handle: handle?.handle
    )

    self.currentSession = session

    return completionsResponse(session: session, options: options, sourcekitd: sourcekitd)
  }

  func handleCompleteUpdate(_ request: SKDRequestDictionaryReader) throws -> SKDResponseDictionaryBuilder {
    let sourcekitd = request.sourcekitd
    let location = try self.requestLocation(request)

    let options: SKDRequestDictionaryReader? = request[sourcekitd.keys.codeCompleteOptions]

    guard let session = self.currentSession, session.location == location else {
      throw GenericPluginError(description: "no matching session for \(location)")
    }

    return completionsResponse(session: session, options: options, sourcekitd: sourcekitd)
  }

  func handleCompleteClose(_ dict: SKDRequestDictionaryReader) throws -> SKDResponseDictionaryBuilder {
    let sourcekitd = dict.sourcekitd

    let location = try self.requestLocation(dict)

    guard let session = self.currentSession, session.location == location else {
      throw GenericPluginError(description: "no matching session for \(location)")
    }

    self.currentSession = nil
    return sourcekitd.responseDictionary([:])
  }

  func handleExtendedCompletionRequest(_ request: SKDRequestDictionaryReader) throws -> ExtendedCompletionInfo {
    let sourcekitd = request.sourcekitd
    let keys = sourcekitd.keys

    guard let opaqueID: Int64 = request[keys.identifier] else {
      throw InvalidRequest.missingKey("key.identifier")
    }

    guard let session = self.currentSession else {
      throw GenericPluginError(description: "no matching session for request \(request)")
    }

    let id = CompletionItem.Identifier(opaqueValue: opaqueID)
    guard let info = session.extendedCompletionInfo(for: id) else {
      throw GenericPluginError(description: "unknown completion \(opaqueID) for session at \(session.location)")
    }

    return info
  }

  func handleCompletionDocumentation(_ request: SKDRequestDictionaryReader) throws -> SKDResponseDictionaryBuilder {
    let info = try handleExtendedCompletionRequest(request)

    return request.sourcekitd.responseDictionary([
      request.sourcekitd.keys.docBrief: info.briefDocumentation,
      request.sourcekitd.keys.docFullAsXML: info.fullDocumentationAsXML,
      request.sourcekitd.keys.docComment: info.rawDocumentation,
      request.sourcekitd.keys.associatedUSRs: info.associatedUSRs as [any SKDResponseValue]?,
    ])
  }

  func handleCompletionDiagnostic(_ dict: SKDRequestDictionaryReader) throws -> SKDResponseDictionaryBuilder {
    let info = try handleExtendedCompletionRequest(dict)
    let sourcekitd = dict.sourcekitd

    let severity: sourcekitd_api_uid_t? =
      switch info.diagnostic?.severity {
      case .note: sourcekitd.values.diagNote
      case .remark: sourcekitd.values.diagRemark
      case .warning: sourcekitd.values.diagWarning
      case .error: sourcekitd.values.diagError
      default: nil
      }
    return sourcekitd.responseDictionary([
      sourcekitd.keys.severity: severity,
      sourcekitd.keys.description: info.diagnostic?.description,
    ])
  }

  func handleDependencyUpdated() {
    connection.markCachedCompilerInstanceShouldBeInvalidated()
  }

  func handleSetPopularAPI(_ dict: SKDRequestDictionaryReader) -> SKDResponseDictionaryBuilder {
    let sourcekitd = dict.sourcekitd
    let keys = sourcekitd.keys

    let didUseScoreComponents: Bool

    // Try 'PopularityIndex' scheme first, then fall back to `PopularityTable`
    // scheme.
    if let scopedPopularityDataPath: String = dict[keys.scopedPopularityTablePath] {
      // NOTE: Currently, the client sends setpopularapi before every
      // 'complete.open' because sourcekit might have crashed before it.
      // 'scoped_popularity_table_path' and its content typically do not
      // change in the 'Connection' lifetime, but 'popular_modules'/'notorious_modules'
      // might. We cache the populated table, and use it as long as the these
      // values are the same as the previous request.
      self.connection.updatePopularityIndex(
        scopedPopularityDataPath: scopedPopularityDataPath,
        popularModules: dict[keys.popularModules]?.asStringArray ?? [],
        notoriousModules: dict[keys.notoriousModules]?.asStringArray ?? []
      )
      didUseScoreComponents = true
    } else if let popularityTable = PopularityTable(dict) {
      self.connection.updatePopularAPI(popularityTable: popularityTable)
      didUseScoreComponents = true
    } else {
      let popular: [String] = dict[keys.popular]?.asStringArray ?? []
      let unpopular: [String] = dict[keys.unpopular]?.asStringArray ?? []
      let popularityTable = PopularityTable(popularSymbols: popular, recentSymbols: [], notoriousSymbols: unpopular)
      self.connection.updatePopularAPI(popularityTable: popularityTable)
      didUseScoreComponents = false
    }
    return sourcekitd.responseDictionary([
      keys.useNewAPI: 1,  // Make it possible to detect this was handled by the plugin.
      keys.usedScoreComponents: didUseScoreComponents ? 1 : 0,
    ])
  }

  private func requestLocation(_ dict: SKDRequestDictionaryReader) throws -> Location {
    let keys = dict.sourcekitd.keys
    guard let path: String = dict[keys.sourceFile] else {
      throw InvalidRequest.missingKey("key.sourcefile")
    }
    guard let line: Int = dict[keys.line] else {
      throw InvalidRequest.missingKey("key.line")
    }
    guard let column: Int = dict[keys.column] else {
      throw InvalidRequest.missingKey("key.column")
    }
    return Location(path: path, position: Position(line: line, utf8Column: column))
  }

  private func populateCompletionsXPC(
    _ completions: [CompletionItem],
    in session: CompletionSession,
    into resp: inout SKDResponseDictionaryBuilder,
    sourcekitd: SourceKitD
  ) {
    let keys = sourcekitd.keys

    let options = session.options
    if options.annotateResults {
      resp.set(keys.annotatedTypeName, to: true)
    }

    let results =
      completions.map { item in
        sourcekitd.responseDictionary([
          keys.kind: sourcekitd_api_uid_t(item.kind, sourcekitd: sourcekitd),
          keys.identifier: item.id.opaqueValue,
          keys.name: item.filterText,
          keys.description: item.label,
          keys.sourceText: item.textEdit.newText,
          keys.isSystem: item.isSystem ? 1 : 0,
          keys.numBytesToErase: item.numBytesToErase(from: session.location.position),
          keys.typeName: item.typeName ?? "",  // FIXME: make it optional?
          keys.textMatchScore: item.textMatchScore,
          keys.semanticScore: item.semanticScore,
          keys.semanticScoreComponents: options.includeSemanticComponents ? nil : item.semanticClassification?.asBase64,
          keys.priorityBucket: item.priorityBucket.rawValue,
          keys.hasDiagnostic: item.hasDiagnostic ? 1 : 0,
          keys.groupId: item.groupID,
        ])
      } as [any SKDResponseValue]
    resp.set(sourcekitd.keys.results, to: results)
  }

  private func populateCompletions(
    _ completions: [CompletionItem],
    in session: CompletionSession,
    into resp: inout SKDResponseDictionaryBuilder,
    includeSemanticComponents: Bool,
    sourcekitd: SourceKitD
  ) {
    let keys = sourcekitd.keys

    let options = session.options
    if options.annotateResults {
      resp.set(keys.annotatedTypeName, to: true)
    }

    var builder = CompletionResultsArrayBuilder(
      bufferKind: self.completionResultsBufferKind,
      numResults: completions.count,
      session: session
    )
    for item in completions {
      builder.add(item, includeSemanticComponents: includeSemanticComponents, sourcekitd: sourcekitd)
    }

    let bytes = builder.bytes()
    bytes.withUnsafeBytes { buffer in
      resp.set(keys.results, toCustomBuffer: buffer)
    }
  }

  private func completionsResponse(
    session: CompletionSession,
    options: SKDRequestDictionaryReader?,
    sourcekitd: SourceKitD
  ) -> SKDResponseDictionaryBuilder {
    let keys = sourcekitd.keys
    var response = sourcekitd.responseDictionary([
      keys.unfilteredResultCount: session.totalCount,
      keys.memberAccessTypes: session.memberAccessTypes as [any SKDResponseValue],
    ])

    let filterText = options?[keys.filterText] ?? ""
    let maxResults = CompletionOptions.maxResults(input: options?[keys.maxResults])
    let includeSemanticComponents = (options?[keys.includeSemanticComponents] as Int?) == 1

    let completions = session.completions(matchingFilterText: filterText, maxResults: maxResults)

    if let useXPC: Int = options?[keys.useXPCSerialization], useXPC != 0 {
      self.populateCompletionsXPC(completions, in: session, into: &response, sourcekitd: sourcekitd)
    } else {
      self.populateCompletions(
        completions,
        in: session,
        into: &response,
        includeSemanticComponents: includeSemanticComponents,
        sourcekitd: sourcekitd
      )
    }
    return response
  }
}

extension sourcekitd_api_uid_t {
  init(_ itemKind: CompletionItem.ItemKind, isRef: Bool = false, sourcekitd: SourceKitD) {
    switch itemKind {
    case .module:
      self = isRef ? sourcekitd.values.refModule : sourcekitd.values.declModule
    case .class:
      self = isRef ? sourcekitd.values.refClass : sourcekitd.values.declClass
    case .actor:
      self = isRef ? sourcekitd.values.refActor : sourcekitd.values.declActor
    case .struct:
      self = isRef ? sourcekitd.values.refStruct : sourcekitd.values.declStruct
    case .enum:
      self = isRef ? sourcekitd.values.refEnum : sourcekitd.values.declEnum
    case .enumElement:
      self = isRef ? sourcekitd.values.refEnumElement : sourcekitd.values.declEnumElement
    case .protocol:
      self = isRef ? sourcekitd.values.refProtocol : sourcekitd.values.declProtocol
    case .associatedType:
      self = isRef ? sourcekitd.values.refAssociatedType : sourcekitd.values.declAssociatedType
    case .typeAlias:
      self = isRef ? sourcekitd.values.refTypeAlias : sourcekitd.values.declTypeAlias
    case .genericTypeParam:
      self = isRef ? sourcekitd.values.refGenericTypeParam : sourcekitd.values.declGenericTypeParam
    case .constructor:
      self = isRef ? sourcekitd.values.refConstructor : sourcekitd.values.declConstructor
    case .destructor:
      self = isRef ? sourcekitd.values.refDestructor : sourcekitd.values.declDestructor
    case .subscript:
      self = isRef ? sourcekitd.values.refSubscript : sourcekitd.values.declSubscript
    case .staticMethod:
      self = isRef ? sourcekitd.values.refMethodStatic : sourcekitd.values.declMethodStatic
    case .instanceMethod:
      self = isRef ? sourcekitd.values.refMethodInstance : sourcekitd.values.declMethodInstance
    case .prefixOperatorFunction:
      self = isRef ? sourcekitd.values.refFunctionPrefixOperator : sourcekitd.values.declFunctionPrefixOperator
    case .postfixOperatorFunction:
      self = isRef ? sourcekitd.values.refFunctionPostfixOperator : sourcekitd.values.declFunctionPostfixOperator
    case .infixOperatorFunction:
      self = isRef ? sourcekitd.values.refFunctionInfixOperator : sourcekitd.values.declFunctionInfixOperator
    case .freeFunction:
      self = isRef ? sourcekitd.values.refFunctionFree : sourcekitd.values.declFunctionFree
    case .staticVar:
      self = isRef ? sourcekitd.values.refVarStatic : sourcekitd.values.declVarStatic
    case .instanceVar:
      self = isRef ? sourcekitd.values.refVarInstance : sourcekitd.values.declVarInstance
    case .localVar:
      self = isRef ? sourcekitd.values.refVarLocal : sourcekitd.values.declVarLocal
    case .globalVar:
      self = isRef ? sourcekitd.values.refVarGlobal : sourcekitd.values.declVarGlobal
    case .precedenceGroup:
      self = isRef ? sourcekitd.values.refPrecedenceGroup : sourcekitd.values.declPrecedenceGroup
    case .macro:
      self = isRef ? sourcekitd.values.refMacro : sourcekitd.values.declMacro
    case .keyword:
      self = sourcekitd.values.completionKindKeyword
    case .operator:
      // FIXME: special operator ?
      self = sourcekitd.values.completionKindPattern
    case .literal:
      // FIXME: special literal ?
      self = sourcekitd.values.completionKindKeyword
    case .pattern:
      self = sourcekitd.values.completionKindPattern
    case .unknown:
      // FIXME: special unknown ?
      self = sourcekitd.values.completionKindKeyword
    }
  }
}
