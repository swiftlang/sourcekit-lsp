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
import SourceKitD

/// Represents a code completion session.
///
/// A code completion session is code completion invoked at a specific location. We might filter results as the user
/// types more characters but the fundamental set of results doesn't change during the session. Invoking code completion
/// at a different location or making an edit to the source file that doesn't filter the code completion results should
/// start a new completion session.
final class CompletionSession {
  /// The connection to sourcekitd from which we get the raw set of results.
  private let connection: Connection

  /// The location at which code completion was invoked.
  let location: Location

  /// A handle to the set of results for this session in sourcekitd. This allows us to retrieve additional information
  /// for each code completion item from sourcekitd.
  let response: swiftide_api_completion_response_t

  /// The list of code completion items available in this session, without any filters applied.
  let items: [ASTCompletionItem]

  /// The filter names for all code completion items in a `CandidateBatch`, which is used for sorting.
  let filterCandidates: CandidateBatch

  /// Information about popular symbols to influence scoring.
  private let popularityIndex: PopularityIndex?
  private let popularityTable: PopularityTable?

  /// Information about the code completion session that applies to all completion items, like what kind of completion
  /// we are performing (member completion, global completion, ...).
  private let context: CompletionContext

  /// Completion options that were set by client when the code completion session was opened.
  let options: CompletionOptions

  /// Convenience accessor to the `SourceKitD` instance.
  var sourcekitd: SourceKitD { connection.sourcekitd }

  var logger: Logger { connection.logger }

  init(
    connection: Connection,
    location: Location,
    response: swiftide_api_completion_response_t,
    options: CompletionOptions
  ) {
    let sourcekitd = connection.sourcekitd
    self.connection = connection
    self.location = location
    self.response = response
    self.options = options
    self.popularityIndex = connection.popularityIndex
    self.popularityTable = connection.popularityTable

    let completionKind = CompletionContext.Kind(connection.sourcekitd.ideApi.completion_result_get_kind(response))

    var memberAccessTypes: [String] = []
    sourcekitd.ideApi.completion_result_foreach_baseexpr_typename(response) { charPtr in
      memberAccessTypes.append(String(cString: charPtr!))
      return false
    }
    var baseExprScope: PopularityIndex.Scope? = nil
    if let popularityIndex = popularityIndex {
      // Use the first scope found in 'popularityIndex'.
      for typeName in memberAccessTypes {
        let scope = PopularityIndex.Scope(string: typeName)
        if popularityIndex.isKnownScope(scope) {
          baseExprScope = scope
          break
        }
      }
    }

    let context = CompletionContext(
      kind: completionKind,
      memberAccessTypes: memberAccessTypes,
      baseExprScope: baseExprScope
    )
    self.context = context

    var candidateStrings: [String] = []

    var items: [ASTCompletionItem] = []
    sourcekitd.ideApi.completion_result_get_completions(response) { itemsPtr, filterPtr, numItems in
      items.reserveCapacity(Int(numItems))
      candidateStrings.reserveCapacity(Int(numItems))
      let citems = UnsafeBufferPointer(start: itemsPtr, count: Int(numItems))
      let cfilters = UnsafeBufferPointer(start: filterPtr, count: Int(numItems))
      for i in 0..<Int(numItems) {
        let citem = citems[i]
        let cfilter = cfilters[i]
        let item = ASTCompletionItem(
          citem!,
          filterName: cfilter,
          completionKind: context.kind,
          index: UInt32(i),
          sourcekitd: sourcekitd
        )
        candidateStrings.append(item.filterName)
        items.append(item)
      }
    }

    self.items = items
    self.filterCandidates = CandidateBatch(candidates: candidateStrings, contentType: .codeCompletionSymbol)
    precondition(items.count == filterCandidates.count)
  }

  var totalCount: Int {
    return items.count
  }

  func completions(matchingFilterText filterText: String, maxResults: Int) -> [CompletionItem] {
    let sorting = CompletionSorting(filterText: filterText, in: self)
    let range =
      location.position..<Position(line: location.line, utf8Column: location.utf8Column + filterText.utf8.count)
    return sorting.withScoredAndFilter(maxResults: maxResults) { (matches) -> [CompletionItem] in
      var nextGroupId = 1  // NOTE: Never use zero. 0 can be considered null groupID.
      var baseNameToGroupId: [String: Int] = [:]

      return matches.map {
        CompletionItem(
          items[$0.index],
          score: $0.score,
          in: self,
          completionReplaceRange: range,
          groupID: { (baseName: String) -> Int in
            if let entry = baseNameToGroupId[baseName] {
              return entry
            } else {
              let groupId = nextGroupId
              baseNameToGroupId[baseName] = groupId
              nextGroupId += 1
              return groupId
            }
          }
        )
      }
    }
  }

  deinit {
    sourcekitd.ideApi.completion_result_dispose(response)
  }

  func popularity(ofSymbol name: String, inModule module: String?) -> Popularity? {
    guard let popularityIndex = self.popularityIndex else {
      // Fall back to deprecated 'popularityTable'.
      if let popularityTable = self.popularityTable {
        return popularityTable.popularity(symbol: name, module: module)
      }

      return nil
    }

    let shouldUseBaseExprScope: Bool
    // Use the base expression scope, for member completions.
    switch completionKind {
    case .dotExpr, .unresolvedMember, .postfixExpr, .keyPathExprSwift, .keyPathExprObjC:
      shouldUseBaseExprScope = true
    default:
      // FIXME: 'baseExprScope' might still be populated for implicit self
      // members. e.g. global expression completion in a method.
      // We might want to use `baseExprScope` if the symbol is a type member.
      shouldUseBaseExprScope = false
    }

    let scope: PopularityIndex.Scope
    // 'baseExprScope == nil' means the 'PopularityIndex' doesn't know the scope.
    // Fallback to the symbol module scope.
    if shouldUseBaseExprScope, let baseExprScope = context.baseExprScope {
      scope = baseExprScope
    } else {
      guard let module = module else {
        // Keywords, etc. don't belong to any module.
        return nil
      }
      scope = PopularityIndex.Scope(container: nil, module: module)
    }

    // Extract the base name from 'name'.
    let baseName: String
    if let parenIdx = name.firstIndex(of: "(") {
      baseName = String(name[..<parenIdx])
    } else {
      baseName = name
    }

    return popularityIndex.popularity(of: PopularityIndex.Symbol(name: baseName, scope: scope))
  }

  func extendedCompletionInfo(for id: CompletionItem.Identifier) -> ExtendedCompletionInfo? {
    return ExtendedCompletionInfo(session: self, index: Int(id.index))
  }

  var completionKind: CompletionContext.Kind { context.kind }
  var memberAccessTypes: [String] { context.memberAccessTypes }
}

/// Information about code completion items that is not returned to the client with the initial results but that the
/// client needs to request for each item with a separate request. It is intended that the client only requests this
/// information when more information about a code completion items should be displayed, eg. because the user selected
/// it.
struct ExtendedCompletionInfo {
  private let session: CompletionSession

  /// The index of the item to get extended information for in `session.items`.
  private let index: Int

  private var rawItem: swiftide_api_completion_item_t { session.items[index].impl }

  init(session: CompletionSession, index: Int) {
    self.session = session
    self.index = index
  }

  var briefDocumentation: String? {
    var result: String? = nil
    session.sourcekitd.ideApi.completion_item_get_doc_brief(session.response, rawItem) {
      if let cstr = $0 {
        result = String(cString: cstr)
      }
    }
    return result
  }

  var fullDocumentation: String? {
    var result: String? = nil
    session.sourcekitd.ideApi.completion_item_get_doc_full_copy?(session.response, rawItem) {
      if let cstr = $0 {
        result = String(cString: cstr)
        free(cstr)
      }
    }
    return result
  }

  var associatedUSRs: [String] {
    var result: [String] = []
    session.sourcekitd.ideApi.completion_item_get_associated_usrs(session.response, rawItem) { ptr, len in
      result.reserveCapacity(Int(len))
      for usr in UnsafeBufferPointer(start: ptr, count: Int(len)) {
        if let cstr = usr {
          result.append(String(cString: cstr))
        }
      }
    }
    return result
  }

  var diagnostic: CompletionItem.Diagnostic? {
    var result: CompletionItem.Diagnostic? = nil
    session.sourcekitd.ideApi.completion_item_get_diagnostic(session.response, rawItem) { severity, message in
      if let severity = CompletionItem.Diagnostic.Severity(severity) {
        result = .init(severity: severity, description: String(cString: message!))
      }
    }
    return result
  }
}

extension CompletionItem.Diagnostic.Severity {
  init?(_ ideValue: swiftide_api_completion_diagnostic_severity_t) {
    switch ideValue {
    case SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_ERROR:
      self = .error
    case SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_WARNING:
      self = .warning
    case SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_REMARK:
      self = .remark
    case SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_NOTE:
      self = .note
    case SWIFTIDE_COMPLETION_DIAGNOSTIC_SEVERITY_NONE:
      return nil
    default:
      // FIXME: Handle unknown severity?
      return nil
    }
  }
}
