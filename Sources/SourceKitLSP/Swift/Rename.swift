//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LSPLogging
import LanguageServerProtocol
import SKSupport
import SourceKitD

/// A parsed representation of a name that may be disambiguated by its argument labels.
///
/// ### Examples
///  - `foo(a:b:)`
///  - `foo(_:b:)`
///  - `foo` if no argument labels are specified, eg. for a variable.
fileprivate struct CompoundDeclName {
  enum CompoundDeclNameParsingError: Error, CustomStringConvertible {
    case missingClosingParenthesis
    case closingParenthesisNotAtEnd

    var description: String {
      switch self {
      case .missingClosingParenthesis: "Name contains '(' but no matching ')'"
      case .closingParenthesisNotAtEnd: "Additional text after ')'"
      }
    }
  }

  /// The parameter of a compound decl name, which can either be the parameter's name or `_` to indicate that the
  /// parameter is unnamed.
  enum Parameter: Equatable {
    case label(String)
    case wildcard

    var stringOrWildcard: String {
      switch self {
      case .label(let str): return str
      case .wildcard: return "_"
      }
    }

    var stringOrEmpty: String {
      switch self {
      case .label(let str): return str
      case .wildcard: return ""
      }
    }
  }

  let baseName: String
  let parameters: [Parameter]

  /// Parse a compound decl name into its base names and parameters.
  init(_ compoundDeclName: String) throws {
    guard let openParen = compoundDeclName.firstIndex(of: "(") else {
      // We don't have a compound name. Everything is the base name
      self.baseName = compoundDeclName
      self.parameters = []
      return
    }
    self.baseName = String(compoundDeclName[..<openParen])
    guard let closeParen = compoundDeclName.firstIndex(of: ")") else {
      throw CompoundDeclNameParsingError.missingClosingParenthesis
    }
    guard compoundDeclName.index(after: closeParen) == compoundDeclName.endIndex else {
      throw CompoundDeclNameParsingError.closingParenthesisNotAtEnd
    }
    let parametersText = compoundDeclName[compoundDeclName.index(after: openParen)..<closeParen]
    // Split by `:` to get the parameter names. Drop the last element so that we don't have a trailing empty element
    // after the last `:`.
    let parameterStrings = parametersText.split(separator: ":", omittingEmptySubsequences: false).dropLast()
    parameters = parameterStrings.map {
      switch $0 {
      case "", "_": return .wildcard
      default: return .label(String($0))
      }
    }
  }
}

/// The kind of range that a `SyntacticRenamePiece` can be.
fileprivate enum SyntacticRenamePieceKind {
  /// The base name of a function or the name of a variable, which can be renamed.
  ///
  /// ### Examples
  /// - `foo` in `func foo(a b: Int)`.
  /// - `foo` in `let foo = 1`
  case baseName

  /// The base name of a function-like declaration that cannot be renamed
  ///
  /// ### Examples
  /// - `init` in `init(a: Int)`
  /// - `subscript` in `subscript(a: Int) -> Int`
  case keywordBaseName

  /// The internal parameter name (aka. second name) inside a function declaration
  ///
  /// ### Examples
  /// - ` b` in `func foo(a b: Int)`
  case parameterName

  /// Same as `parameterName` but cannot be removed if it is the same as the parameter's first name. This only happens
  /// for subscripts where parameters are unnamed by default unless they have both a first and second name.
  ///
  /// ### Examples
  /// The second ` a` in `subscript(a a: Int)`
  case noncollapsibleParameterName

  /// The external argument label of a function parameter
  ///
  /// ### Examples
  /// - `a` in `func foo(a b: Int)`
  /// - `a` in `func foo(a: Int)`
  case declArgumentLabel

  /// The argument label inside a call.
  ///
  /// ### Examples
  /// - `a` in `foo(a: 1)`
  case callArgumentLabel

  /// The colon after an argument label inside a call. This is reported so it can be removed if the parameter becomes
  /// unnamed.
  ///
  /// ### Examples
  /// - `: ` in `foo(a: 1)`
  case callArgumentColon

  /// An empty range that point to the position before an unnamed argument. This is used to insert the argument label
  /// if an unnamed parameter becomes named.
  ///
  /// ### Examples
  /// - An empty range before `1` in `foo(1)`, which could expand to `foo(a: 1)`
  case callArgumentCombined

  /// The argument label in a compound decl name.
  ///
  /// ### Examples
  /// - `a` in `foo(a:)`
  case selectorArgumentLabel

  init?(_ uid: sourcekitd_uid_t, keys: sourcekitd_keys) {
    switch uid {
    case keys.renameRangeBase: self = .baseName
    case keys.renameRangeCallArgColon: self = .callArgumentColon
    case keys.renameRangeCallArgCombined: self = .callArgumentCombined
    case keys.renameRangeCallArgLabel: self = .callArgumentLabel
    case keys.renameRangeDeclArgLabel: self = .declArgumentLabel
    case keys.renameRangeKeywordBase: self = .keywordBaseName
    case keys.renameRangeNoncollapsibleParam: self = .noncollapsibleParameterName
    case keys.renameRangeParam: self = .parameterName
    case keys.renameRangeSelectorArgLabel: self = .selectorArgumentLabel
    default: return nil
    }
  }
}

/// A single “piece” that is used for renaming a compound function name.
///
/// See `SyntacticRenamePieceKind` for the different rename pieces that exist.
///
/// ### Example
/// `foo(x: 1)` is represented by three pieces
/// - The base name `foo`
/// - The parameter name `x`
/// - The call argument colon `: `.
fileprivate struct SyntacticRenamePiece {
  /// The range that represents this piece of the name
  let range: Range<Position>

  /// The kind of the rename piece.
  let kind: SyntacticRenamePieceKind

  /// If this piece belongs to a parameter, the index of that parameter (zero-based) or `nil` if this is the base name
  /// piece.
  let parameterIndex: Int?

  /// Create a `SyntacticRenamePiece` from a `sourcekitd` response.
  init?(_ dict: SKDResponseDictionary, in snapshot: DocumentSnapshot, keys: sourcekitd_keys) {
    guard let line: Int = dict[keys.line],
      let column: Int = dict[keys.column],
      let endLine: Int = dict[keys.endline],
      let endColumn: Int = dict[keys.endcolumn],
      let kind: sourcekitd_uid_t = dict[keys.kind]
    else {
      return nil
    }
    guard
      let start = snapshot.positionOf(zeroBasedLine: line - 1, utf8Column: column - 1),
      let end = snapshot.positionOf(zeroBasedLine: endLine - 1, utf8Column: endColumn - 1)
    else {
      return nil
    }
    guard let kind = SyntacticRenamePieceKind(kind, keys: keys) else {
      return nil
    }

    self.range = start..<end
    self.kind = kind
    self.parameterIndex = dict[keys.argindex] as Int?
  }
}

/// The context in which the location to be renamed occurred.
fileprivate enum SyntacticRenameNameContext {
  /// No syntactic rename ranges for the rename location could be found.
  case unmatched

  /// A name could be found at a requested rename location but the name did not match the specified old name.
  case mismatch

  /// The matched ranges are in active source code (ie. source code that is not an inactive `#if` range).
  case activeCode

  /// The matched ranges are in an inactive `#if` region of the source code.
  case inactiveCode

  /// The matched ranges occur inside a string literal.
  case string

  /// The matched ranges occur inside a `#selector` directive.
  case selector

  /// The matched ranges are within a comment.
  case comment

  init?(_ uid: sourcekitd_uid_t, keys: sourcekitd_keys) {
    switch uid {
    case keys.sourceEditKindActive: self = .activeCode
    case keys.sourceEditKindComment: self = .comment
    case keys.sourceEditKindInactive: self = .inactiveCode
    case keys.sourceEditKindMismatch: self = .mismatch
    case keys.sourceEditKindSelector: self = .selector
    case keys.sourceEditKindString: self = .string
    case keys.sourceEditKindUnknown: self = .unmatched
    default: return nil
    }
  }
}

/// A set of ranges that, combined, represent which edits need to be made to rename a possibly compound name.
///
/// See `SyntacticRenamePiece` for more details.
fileprivate struct SyntacticRenameName {
  let pieces: [SyntacticRenamePiece]
  let category: SyntacticRenameNameContext

  init?(_ dict: SKDResponseDictionary, in snapshot: DocumentSnapshot, keys: sourcekitd_keys) {
    guard let ranges: SKDResponseArray = dict[keys.ranges] else {
      return nil
    }
    self.pieces = ranges.compactMap { SyntacticRenamePiece($0, in: snapshot, keys: keys) }
    guard let categoryUid: sourcekitd_uid_t = dict[keys.category],
      let category = SyntacticRenameNameContext(categoryUid, keys: keys)
    else {
      return nil
    }
    self.category = category
  }
}

struct RenameLocation {
  /// The line of the identifier to be renamed (1-based).
  let line: Int
  /// The column of the identifier to be renamed in UTF-8 bytes (1-based).
  let utf8Column: Int
  let usage: RelatedIdentifier.Usage
}

private extension DocumentSnapshot {
  init(_ url: URL, language: Language) throws {
    let contents = try String(contentsOf: url)
    self.init(uri: DocumentURI(url), language: language, version: 0, lineTable: LineTable(contents))
  }
}

extension SwiftLanguageServer {
  /// From a list of rename locations compute the list of `SyntacticRenameName`s that define which ranges need to be 
  /// edited to rename a compound decl name.
  ///  
  /// - Parameters:
  ///   - renameLocations: The locations to rename
  ///   - oldName: The compound decl name that the declaration had before the rename. Used to verify that the rename 
  ///     locations match that name. Eg. `myFunc(argLabel:otherLabel:)` or `myVar`
  ///   - snapshot: If the document has been modified from the on-disk version, the current snapshot. `nil` to read the
  ///     file contents from disk.
  private func getSyntacticRenameRanges(
    renameLocations: [RenameLocation],
    oldName: String,
    in snapshot: DocumentSnapshot
  ) async throws -> [SyntacticRenameName] {
    let locations = SKDRequestArray(sourcekitd: sourcekitd)
    locations += renameLocations.map { renameLocation in
      let skRenameLocation = SKDRequestDictionary(sourcekitd: sourcekitd)
      skRenameLocation[keys.line] = renameLocation.line
      skRenameLocation[keys.column] = renameLocation.utf8Column
      skRenameLocation[keys.nameType] = renameLocation.usage.uid(keys: keys)
      return skRenameLocation
    }
    let renameLocation = SKDRequestDictionary(sourcekitd: sourcekitd)
    renameLocation[keys.locations] = locations
    renameLocation[keys.name] = oldName

    let renameLocations = SKDRequestArray(sourcekitd: sourcekitd)
    renameLocations.append(renameLocation)

    let skreq = SKDRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.find_syntactic_rename_ranges
    skreq[keys.sourcefile] = snapshot.uri.pseudoPath
    // find-syntactic-rename-ranges is a syntactic sourcekitd request that doesn't use the in-memory file snapshot.
    // We need to send the source text again.
    skreq[keys.sourcetext] = snapshot.text
    skreq[keys.renamelocations] = renameLocations

    let syntacticRenameRangesResponse = try await sourcekitd.send(skreq, fileContents: snapshot.text)
    guard let categorizedRanges: SKDResponseArray = syntacticRenameRangesResponse[keys.categorizedranges] else {
      throw ResponseError.internalError("sourcekitd did not return categorized ranges")
    }

    return categorizedRanges.compactMap { SyntacticRenameName($0, in: snapshot, keys: keys) }
  }

  public func rename(_ request: RenameRequest) async throws -> WorkspaceEdit? {
    let snapshot = try self.documentManager.latestSnapshot(request.textDocument.uri)

    let relatedIdentifiers = try await self.relatedIdentifiers(
      at: request.position,
      in: snapshot,
      includeNonEditableBaseNames: true
    )
    guard let oldName = relatedIdentifiers.name else {
      throw ResponseError.unknown("Running sourcekit-lsp with a version of sourcekitd that does not support rename")
    }
    
    try Task.checkCancellation()

    let renameLocations = relatedIdentifiers.relatedIdentifiers.compactMap { (relatedIdentifier) -> RenameLocation? in
      let position = relatedIdentifier.range.lowerBound
      guard let utf8Column = snapshot.lineTable.utf8ColumnAt(line: position.line, utf16Column: position.utf16index)
      else {
        logger.fault("Unable to find UTF-8 column for \(position.line):\(position.utf16index)")
        return nil
      }
      return RenameLocation(line: position.line + 1, utf8Column: utf8Column + 1, usage: relatedIdentifier.usage)
    }
    
    try Task.checkCancellation()

    let edits = try await renameRanges(from: renameLocations, in: snapshot, oldName: oldName, newName: try CompoundDeclName(request.newName))

    return WorkspaceEdit(changes: [
      snapshot.uri: edits
    ])
  }

  private func renameRanges(from renameLocations: [RenameLocation], in snapshot: DocumentSnapshot, oldName oldNameString: String, newName: CompoundDeclName) async throws -> [TextEdit] {
    let compoundRenameRanges = try await getSyntacticRenameRanges(renameLocations: renameLocations, oldName: oldNameString, in: snapshot)
    let oldName = try CompoundDeclName(oldNameString)

    try Task.checkCancellation()

    return compoundRenameRanges.flatMap { (compoundRenameRange) -> [TextEdit] in
      switch compoundRenameRange.category {
      case .unmatched, .mismatch:
        // The location didn't match. Don't rename it
        return []
      case .activeCode, .inactiveCode, .selector:
        // Occurrences in active code and selectors should always be renamed.
        // Inactive code is currently never returned by sourcekitd.
        break
      case .string, .comment:
        // We currently never get any results in strings or comments because the related identifiers request doesn't
        // provide any locations inside strings or comments. We would need to have a textual index to find these
        // locations.
        return []
      }
      return compoundRenameRange.pieces.compactMap { (piece) -> TextEdit? in
        if piece.kind == .baseName {
          return TextEdit(range: piece.range, newText: newName.baseName)
        } else if piece.kind == .keywordBaseName {
          // Keyword base names can't be renamed
          return nil
        }

        guard let parameterIndex = piece.parameterIndex,
          parameterIndex < newName.parameters.count,
          parameterIndex < oldName.parameters.count
        else {
          // Be lenient and just keep the old parameter names if the new name doesn't specify them, eg. if we are
          // renaming `func foo(a: Int, b: Int)` and the user specified `bar(x:)` as the new name.
          return nil
        }
        let newParameterName = newName.parameters[parameterIndex]
        let oldParameterName = oldName.parameters[parameterIndex]
        switch piece.kind {
        case .parameterName:
          if newParameterName == .wildcard, piece.range.isEmpty, case .label(let oldParameterLabel) = oldParameterName {
            // We are changing a named parameter to an unnamed one. If the parameter didn't have an internal parameter
            // name, we need to transfer the previously external parameter name to be the internal one.
            // E.g. `func foo(a: Int)` becomes `func foo(_ a: Int)`.
            return TextEdit(range: piece.range, newText: " " + oldParameterLabel)
          } else if let original = snapshot.lineTable[piece.range],
            case .label(let newParameterLabel) = newParameterName,
            newParameterLabel.trimmingCharacters(in: .whitespaces) == original.trimmingCharacters(in: .whitespaces)
          {
            // We are changing the external parameter name to be the same one as the internal parameter name. The
            // internal name is thus no longer needed. Drop it.
            // Eg. an old declaration `func foo(_ a: Int)` becomes `func foo(a: Int)` when renaming the parameter to `a`
            return TextEdit(range: piece.range, newText: "")
          } else {
            // In all other cases, don't touch the internal parameter name. It's not part of the public API.
            return nil
          }
        case .noncollapsibleParameterName:
          // Noncollapsible parameter names should never be renamed because they are the same as `parameterName` but
          // never fall into one of the two categories above.
          return nil
        case .declArgumentLabel:
          if piece.range.isEmpty {
            // If we are inserting a new external argument label where there wasn't one before, add a space after it to
            // separate it from the internal name.
            // E.g. `subscript(a: Int)` becomes `subscript(a a: Int)`.
            return TextEdit(range: piece.range, newText: newParameterName.stringOrWildcard + " ")
          } else {
            // Otherwise, just update the name.
            return TextEdit(range: piece.range, newText: newParameterName.stringOrWildcard)
          }
        case .callArgumentLabel:
          // Argument labels of calls are just updated.
          return TextEdit(range: piece.range, newText: newParameterName.stringOrEmpty)
        case .callArgumentColon:
          if case .wildcard = newParameterName {
            // If the parameter becomes unnamed, remove the colon after the argument name.
            return TextEdit(range: piece.range, newText: "")
          } else {
            return nil
          }
        case .callArgumentCombined:
          if case .label(let newParameterLabel) = newParameterName {
            // If an unnamed parameter becomes named, insert the new name and a colon.
            return TextEdit(range: piece.range, newText: newParameterLabel + ": ")
          } else {
            return nil
          }
        case .selectorArgumentLabel:
          return TextEdit(range: piece.range, newText: newParameterName.stringOrWildcard)
        case .baseName, .keywordBaseName:
          preconditionFailure("Handled above")
        }
      }
    }
  }
}

extension LineTable {
  subscript(range: Range<Position>) -> Substring? {
    guard let start = self.stringIndexOf(line: range.lowerBound.line, utf16Column: range.lowerBound.utf16index),
      let end = self.stringIndexOf(line: range.upperBound.line, utf16Column: range.upperBound.utf16index)
    else {
      return nil
    }
    return self.content[start..<end]
  }
}
