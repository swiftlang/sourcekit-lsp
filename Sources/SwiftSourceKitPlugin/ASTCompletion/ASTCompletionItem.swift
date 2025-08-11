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
import SwiftExtensions

/// A single code completion result returned from sourcekitd + additional information. This is effectively a wrapper
/// around `swiftide_api_completion_item_t` that caches the properties which have already been retrieved.
/// - Note: There can many be `ASTCompletionItem` instances (e.g. global completion has ~100k items), make sure to check
///   layout when adding new fields to ensure we're not wasting a bunch of space.
///   (i.e.,`heap --showInternalFragmentation process_name`)
final class ASTCompletionItem {
  let impl: swiftide_api_completion_item_t

  /// The string that should be used to match against what the user type.
  var filterName: String {
    return _filterName.cachedValueOrCompute {
      filterNameCString != nil ? String(cString: filterNameCString!) : ""
    }
  }
  let filterNameCString: UnsafePointer<CChar>?
  private var _filterName: LazyValue<String> = .uninitialized

  /// The label with which the item should be displayed in an IDE
  func label(in session: CompletionSession) -> String {
    return _label.cachedValueOrCompute {
      var value: String?
      session.sourcekitd.ideApi.completion_item_get_label(session.response, impl, session.options.annotateResults) {
        value = String(cString: $0!)
      }
      return value!
    }
  }
  private var _label: LazyValue<String> = .uninitialized

  func sourceText(in session: CompletionSession) -> String {
    return _sourceText.cachedValueOrCompute {
      var value: String?
      session.sourcekitd.ideApi.completion_item_get_source_text(session.response, impl) {
        value = String(cString: $0!)
      }
      return value!
    }
  }
  private var _sourceText: LazyValue<String> = .uninitialized

  /// The type that the code completion item produces.
  ///
  /// Eg. the type of a variable or the return type of a function. `nil` for completions that don't have a type, like
  /// keywords.
  func typeName(in session: CompletionSession) -> String? {
    return _typeName.cachedValueOrCompute {
      var value: String?
      session.sourcekitd.ideApi.completion_item_get_type_name(session.response, impl, session.options.annotateResults) {
        if let cstr = $0 {
          value = String(cString: cstr)
        }
      }
      return value
    }
  }
  private var _typeName: LazyValue<String?> = .uninitialized

  /// The module that defines the code completion item or `nil` if the item is not defined in a module, like a keyword.
  func moduleName(in session: CompletionSession) -> String? {
    return _moduleName.cachedValueOrCompute {
      var value: String?
      session.sourcekitd.ideApi.completion_item_get_module_name(session.response, impl) {
        if let cstr = $0 {
          value = String(cString: cstr)
        } else {
          value = nil
        }
      }
      if value == "" {
        return nil
      }
      return value
    }
  }
  private var _moduleName: LazyValue<String?> = .uninitialized

  func priorityBucket(in session: CompletionSession) -> CompletionItem.PriorityBucket {
    return _priorityBucket.cachedValueOrCompute {
      CompletionItem.PriorityBucket(self, in: session)
    }
  }
  private var _priorityBucket: LazyValue<CompletionItem.PriorityBucket> = .uninitialized

  let completionKind: CompletionContext.Kind

  let index: UInt32

  func semanticScore(in session: CompletionSession) -> Double {
    return _semanticScore.cachedValueOrCompute {
      let semanticClassification = semanticClassification(in: session)
      self.semanticClassification = semanticClassification
      return semanticClassification.score
    }
  }
  private var _semanticScore: LazyValue<Double> = .uninitialized

  private func semanticClassification(in session: CompletionSession) -> SemanticClassification {
    var module = moduleName(in: session)
    if let baseModule = module?.split(separator: ".", maxSplits: 1).first {
      // `PopularityIndex` is keyed on base module names.
      // For example: "AppKit.NSImage" -> "AppKit".
      module = String(baseModule)
    }
    let popularity = session.popularity(
      ofSymbol: filterName,
      inModule: module
    )
    return SemanticClassification(
      availability: availability(in: session),
      completionKind: semanticScoreCompletionKind(in: session),
      flair: flair(in: session),
      moduleProximity: moduleProximity(in: session),
      popularity: popularity ?? .none,
      scopeProximity: scopeProximity(in: session),
      structuralProximity: structuralProximity(in: session),
      synchronicityCompatibility: synchronicityCompatibility(in: session),
      typeCompatibility: typeCompatibility(in: session)
    )
  }
  var semanticClassification: SemanticClassification? = nil

  var kind: CompletionItem.ItemKind

  func semanticContext(in session: CompletionSession) -> CompletionItem.SemanticContext {
    .init(
      swiftide_api_completion_semantic_context_t(session.sourcekitd.ideApi.completion_item_get_semantic_context(impl))
    )
  }

  func typeRelation(in session: CompletionSession) -> CompletionItem.TypeRelation {
    .init(swiftide_api_completion_type_relation_t(session.sourcekitd.ideApi.completion_item_get_type_relation(impl)))
  }

  func numBytesToErase(in session: CompletionSession) -> Int {
    Int(session.sourcekitd.ideApi.completion_item_get_num_bytes_to_erase(impl))
  }

  func notRecommended(in session: CompletionSession) -> Bool {
    session.sourcekitd.ideApi.completion_item_is_not_recommended(impl)
  }

  func notRecommendedReason(in session: CompletionSession) -> NotRecommendedReason? {
    guard notRecommended(in: session) else {
      return nil
    }
    return NotRecommendedReason(impl, sourcekitd: session.sourcekitd)
  }

  func isSystem(in session: CompletionSession) -> Bool { session.sourcekitd.ideApi.completion_item_is_system(impl) }

  func hasDiagnostic(in session: CompletionSession) -> Bool {
    session.sourcekitd.ideApi.completion_item_has_diagnostic(impl)
  }

  init(
    _ cresult: swiftide_api_completion_item_t,
    filterName: UnsafePointer<CChar>?,
    completionKind: CompletionContext.Kind,
    index: UInt32,
    sourcekitd: SourceKitD
  ) {
    self.impl = cresult
    self.filterNameCString = filterName
    self.completionKind = completionKind
    self.index = index
    self.kind = .init(
      swiftide_api_completion_item_kind_t(sourcekitd.ideApi.completion_item_get_kind(impl)),
      associatedKind: sourcekitd.ideApi.completion_item_get_associated_kind(impl)
    )
  }

  enum NotRecommendedReason {
    case softDeprecated
    case deprecated
    case redundantImport
    case redundantImportImplicit
    case invalidAsyncContext
    case crossActorReference
    case variableUsedInOwnDefinition
    case nonAsyncAlternativeUsedInAsyncContext

    init?(_ item: swiftide_api_completion_item_t, sourcekitd: SourceKitD) {
      let rawReason = sourcekitd.ideApi.completion_item_not_recommended_reason(item)
      switch swiftide_api_completion_not_recommended_reason_t(rawReason) {
      case SWIFTIDE_COMPLETION_NOT_RECOMMENDED_NONE:
        return nil
      case SWIFTIDE_COMPLETION_NOT_RECOMMENDED_REDUNDANT_IMPORT:
        self = .redundantImport
      case SWIFTIDE_COMPLETION_NOT_RECOMMENDED_DEPRECATED:
        self = .deprecated
      case SWIFTIDE_COMPLETION_NOT_RECOMMENDED_INVALID_ASYNC_CONTEXT:
        self = .invalidAsyncContext
      case SWIFTIDE_COMPLETION_NOT_RECOMMENDED_CROSS_ACTOR_REFERENCE:
        self = .crossActorReference
      case SWIFTIDE_COMPLETION_NOT_RECOMMENDED_VARIABLE_USED_IN_OWN_DEFINITION:
        self = .variableUsedInOwnDefinition
      case SWIFTIDE_COMPLETION_NOT_RECOMMENDED_SOFTDEPRECATED:
        self = .softDeprecated
      case SWIFTIDE_COMPLETION_NOT_RECOMMENDED_REDUNDANT_IMPORT_INDIRECT:
        self = .redundantImportImplicit
      case SWIFTIDE_COMPLETION_NOT_RECOMMENDED_NON_ASYNC_ALTERNATIVE_USED_IN_ASYNC_CONTEXT:
        self = .nonAsyncAlternativeUsedInAsyncContext
      default:
        return nil
      }
    }
  }
}

extension ASTCompletionItem {
  private func semanticScoreCompletionKind(in session: CompletionSession) -> CompletionKind {
    if session.sourcekitd.ideApi.completion_item_get_flair(impl) & SWIFTIDE_COMPLETION_FLAIR_ARGUMENTLABELS.rawValue
      != 0
    {
      return .argumentLabels
    }
    switch kind {
    case .module:
      return .module
    case .class, .actor, .struct, .enum, .protocol, .associatedType, .typeAlias, .genericTypeParam, .precedenceGroup:
      return .type
    case .enumElement:
      return .enumCase
    case .constructor:
      return .initializer
    case .destructor:
      // FIXME: add a "deinit" kind.
      return .function
    case .subscript:
      // FIXME: add a "subscript" kind.
      return .function
    case .staticMethod, .instanceMethod, .freeFunction:
      return .function
    case .operator, .prefixOperatorFunction, .postfixOperatorFunction, .infixOperatorFunction:
      // FIXME: add an "operator kind".
      return .other
    case .staticVar, .instanceVar, .localVar, .globalVar:
      return .variable
    case .keyword:
      return .keyword
    case .literal:
      // FIXME: add a "literal" kind?
      return .other
    case .pattern:
      // FIXME: figure out a kind for this.
      return .other
    case .macro:
      // FIXME: add a "macro" kind?
      return .type
    case .unknown:
      return .unknown
    }
  }

  private func flair(in session: CompletionSession) -> Flair {
    var result: Flair = []
    let skFlair = session.sourcekitd.ideApi.completion_item_get_flair(impl)
    if skFlair & SWIFTIDE_COMPLETION_FLAIR_EXPRESSIONSPECIFIC.rawValue != 0 {
      result.insert(.oldExpressionSpecific_pleaseAddSpecificCaseToThisEnum)
    }
    if skFlair & SWIFTIDE_COMPLETION_FLAIR_SUPERCHAIN.rawValue != 0 {
      result.insert(.chainedCallToSuper)
    }
    if skFlair & SWIFTIDE_COMPLETION_FLAIR_COMMONKEYWORDATCURRENTPOSITION.rawValue != 0 {
      result.insert(.commonKeywordAtCurrentPosition)
    }
    if skFlair & SWIFTIDE_COMPLETION_FLAIR_RAREKEYWORDATCURRENTPOSITION.rawValue != 0 {
      result.insert(.rareKeywordAtCurrentPosition)
    }
    if skFlair & SWIFTIDE_COMPLETION_FLAIR_RARETYPEATCURRENTPOSITION.rawValue != 0 {
      result.insert(.rareKeywordAtCurrentPosition)
    }
    if skFlair & SWIFTIDE_COMPLETION_FLAIR_EXPRESSIONATNONSCRIPTORMAINFILESCOPE.rawValue != 0 {
      result.insert(.expressionAtNonScriptOrMainFileScope)
    }
    return result
  }

  private func moduleProximity(in session: CompletionSession) -> ModuleProximity {
    switch semanticContext(in: session) {
    case .none:
      return .inapplicable
    case .local, .currentNominal, .outsideNominal:
      return .imported(distance: 0)
    case .super:
      // FIXME: we don't know whether the super class is from this module or another.
      return .unspecified
    case .currentModule:
      return .imported(distance: 0)
    case .otherModule:
      let depth = session.sourcekitd.ideApi.completion_item_import_depth(session.response, self.impl)
      if depth == ~0 {
        return .unknown
      } else {
        return .imported(distance: Int(depth))
      }
    }
  }

  private func scopeProximity(in session: CompletionSession) -> ScopeProximity {
    switch semanticContext(in: session) {
    case .none:
      return .inapplicable
    case .local:
      return .local
    case .currentNominal:
      return .container
    case .super:
      return .inheritedContainer
    case .outsideNominal:
      return .outerContainer
    case .currentModule, .otherModule:
      return .global
    }
  }

  private func structuralProximity(in session: CompletionSession) -> StructuralProximity {
    switch kind {
    case .keyword, .literal:
      return .inapplicable
    default:
      return isSystem(in: session) ? .sdk : .project(fileSystemHops: nil)
    }
  }

  func synchronicityCompatibility(in session: CompletionSession) -> SynchronicityCompatibility {
    return notRecommendedReason(in: session) == .invalidAsyncContext ? .incompatible : .compatible
  }

  func typeCompatibility(in session: CompletionSession) -> TypeCompatibility {
    switch typeRelation(in: session) {
    case .identical: return .compatible
    case .convertible: return .compatible
    case .notApplicable: return .inapplicable
    case .unrelated: return .unrelated
    // Note: currently `unknown` in sourcekit usually means there is no context (e.g. statement level), which is
    // equivalent to `inapplicable`. For now, map it that way to avoid spurious penalties.
    case .unknown: return .inapplicable
    case .invalid: return .invalid
    }
  }

  func availability(in session: CompletionSession) -> Availability {
    switch notRecommendedReason(in: session) {
    case .deprecated:
      return .deprecated
    case .softDeprecated:
      return .softDeprecated
    case .invalidAsyncContext, .crossActorReference:
      return .available
    case .redundantImport, .variableUsedInOwnDefinition:
      return .softDeprecated
    case .redundantImportImplicit:
      return .available
    case .nonAsyncAlternativeUsedInAsyncContext:
      return .softDeprecated
    case nil:
      return .available
    }
  }
}

extension CompletionItem {
  init(
    _ astItem: ASTCompletionItem,
    score: CompletionScore,
    in session: CompletionSession,
    completionReplaceRange: Range<Position>,
    groupID: (_ baseName: String) -> Int
  ) {
    self.label = astItem.label(in: session)
    self.filterText = astItem.filterName
    self.module = astItem.moduleName(in: session)
    self.typeName = astItem.typeName(in: session)
    var editRange = completionReplaceRange
    if astItem.numBytesToErase(in: session) > 0 {
      let newCol = editRange.lowerBound.utf8Column - astItem.numBytesToErase(in: session)
      if newCol >= 1 {
        editRange = Position(line: editRange.lowerBound.line, utf8Column: newCol)..<editRange.upperBound
      } else {
        session.logger.error("num_bytes_to_erase crosses line boundary. Resetting num_bytes_to_erase to 0.")
      }
    }
    self.textEdit = TextEdit(range: editRange, newText: astItem.sourceText(in: session))
    self.kind = astItem.kind
    self.isSystem = astItem.isSystem(in: session)
    self.textMatchScore = score.textComponent
    self.priorityBucket = astItem.priorityBucket(in: session)
    self.semanticScore = score.semanticComponent
    self.semanticClassification = astItem.semanticClassification
    self.id = Identifier(index: astItem.index)
    self.hasDiagnostic = astItem.hasDiagnostic(in: session)

    let needsGroupID =
      switch kind {
      case .staticVar, .instanceVar, .localVar, .globalVar:
        // We don't want to group variables with functions that have an equal base name.
        false
      case .keyword:
        false
      default:
        true
      }
    // Set groupId using the name before '('.
    // This allows top-level completions to be grouped together
    // (including the actual type completion).
    // For example:
    // ```
    // MyClass
    // MyClass(test:)
    // MyClass(other:)
    // ```
    if needsGroupID {
      var baseName = filterText
      if let parenIdx = baseName.firstIndex(of: "(") {
        baseName = String(baseName[..<parenIdx])
      }
      self.groupID = groupID(baseName)
    } else {
      self.groupID = nil
    }
  }
}

extension CompletionItem.ItemKind {
  init(_ ckind: swiftide_api_completion_item_kind_t, associatedKind: UInt32) {
    switch ckind {
    case SWIFTIDE_COMPLETION_ITEM_KIND_DECLARATION:
      switch swiftide_api_completion_item_decl_kind_t(associatedKind) {
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_MODULE: self = .module
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_CLASS: self = .class
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_ACTOR: self = .actor
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_STRUCT: self = .struct
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_ENUM: self = .enum
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_ENUMELEMENT: self = .enumElement
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_PROTOCOL: self = .protocol
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_ASSOCIATEDTYPE: self = .associatedType
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_TYPEALIAS: self = .typeAlias
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_GENERICTYPEPARAM: self = .genericTypeParam
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_CONSTRUCTOR: self = .constructor
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_DESTRUCTOR: self = .destructor
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_SUBSCRIPT: self = .subscript
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_STATICMETHOD: self = .staticMethod
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_INSTANCEMETHOD: self = .instanceMethod
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_PREFIXOPERATORFUNCTION: self = .prefixOperatorFunction
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_POSTFIXOPERATORFUNCTION: self = .postfixOperatorFunction
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_INFIXOPERATORFUNCTION: self = .infixOperatorFunction
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_FREEFUNCTION: self = .freeFunction
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_STATICVAR: self = .staticVar
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_INSTANCEVAR: self = .instanceVar
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_LOCALVAR: self = .localVar
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_GLOBALVAR: self = .globalVar
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_PRECEDENCEGROUP: self = .precedenceGroup
      case SWIFTIDE_COMPLETION_ITEM_DECL_KIND_MACRO: self = .macro
      default: self = .unknown
      }
    case SWIFTIDE_COMPLETION_ITEM_KIND_KEYWORD:
      self = .keyword
    case SWIFTIDE_COMPLETION_ITEM_KIND_PATTERN:
      self = .pattern
    case SWIFTIDE_COMPLETION_ITEM_KIND_LITERAL:
      self = .literal
    case SWIFTIDE_COMPLETION_ITEM_KIND_BUILTINOPERATOR:
      self = .operator
    default: self = .unknown
    }
  }
}

extension CompletionContext.Kind {
  init(_ ckind: swiftide_api_completion_kind_t) {
    switch ckind {
    case SWIFTIDE_COMPLETION_KIND_NONE: self = .none
    case SWIFTIDE_COMPLETION_KIND_IMPORT: self = .import
    case SWIFTIDE_COMPLETION_KIND_UNRESOLVEDMEMBER: self = .unresolvedMember
    case SWIFTIDE_COMPLETION_KIND_DOTEXPR: self = .dotExpr
    case SWIFTIDE_COMPLETION_KIND_STMTOREXPR: self = .stmtOrExpr
    case SWIFTIDE_COMPLETION_KIND_POSTFIXEXPRBEGINNING: self = .postfixExprBeginning
    case SWIFTIDE_COMPLETION_KIND_POSTFIXEXPR: self = .postfixExpr
    case SWIFTIDE_COMPLETION_KIND_POSTFIXEXPRPAREN: self = .postfixExprParen
    case SWIFTIDE_COMPLETION_KIND_KEYPATHEXPROBJC: self = .keyPathExprObjC
    case SWIFTIDE_COMPLETION_KIND_KEYPATHEXPRSWIFT: self = .keyPathExprSwift
    case SWIFTIDE_COMPLETION_KIND_TYPEDECLRESULTBEGINNING: self = .typeDeclResultBeginning
    case SWIFTIDE_COMPLETION_KIND_TYPESIMPLEBEGINNING: self = .typeSimpleBeginning
    case SWIFTIDE_COMPLETION_KIND_TYPEIDENTIFIERWITHDOT: self = .typeIdentifierWithDot
    case SWIFTIDE_COMPLETION_KIND_TYPEIDENTIFIERWITHOUTDOT: self = .typeIdentifierWithoutDot
    case SWIFTIDE_COMPLETION_KIND_CASESTMTKEYWORD: self = .caseStmtKeyword
    case SWIFTIDE_COMPLETION_KIND_CASESTMTBEGINNING: self = .caseStmtBeginning
    case SWIFTIDE_COMPLETION_KIND_NOMINALMEMBERBEGINNING: self = .nominalMemberBeginning
    case SWIFTIDE_COMPLETION_KIND_ACCESSORBEGINNING: self = .accessorBeginning
    case SWIFTIDE_COMPLETION_KIND_ATTRIBUTEBEGIN: self = .attributeBegin
    case SWIFTIDE_COMPLETION_KIND_ATTRIBUTEDECLPAREN: self = .attributeDeclParen
    case SWIFTIDE_COMPLETION_KIND_POUNDAVAILABLEPLATFORM: self = .poundAvailablePlatform
    case SWIFTIDE_COMPLETION_KIND_CALLARG: self = .callArg
    case SWIFTIDE_COMPLETION_KIND_LABELEDTRAILINGCLOSURE: self = .labeledTrailingClosure
    case SWIFTIDE_COMPLETION_KIND_RETURNSTMTEXPR: self = .returnStmtExpr
    case SWIFTIDE_COMPLETION_KIND_YIELDSTMTEXPR: self = .yieldStmtExpr
    case SWIFTIDE_COMPLETION_KIND_FOREACHSEQUENCE: self = .forEachSequence
    case SWIFTIDE_COMPLETION_KIND_AFTERPOUNDEXPR: self = .afterPoundExpr
    case SWIFTIDE_COMPLETION_KIND_AFTERPOUNDDIRECTIVE: self = .afterPoundDirective
    case SWIFTIDE_COMPLETION_KIND_PLATFORMCONDITON: self = .platformConditon
    case SWIFTIDE_COMPLETION_KIND_AFTERIFSTMTELSE: self = .afterIfStmtElse
    case SWIFTIDE_COMPLETION_KIND_GENERICREQUIREMENT: self = .genericRequirement
    case SWIFTIDE_COMPLETION_KIND_PRECEDENCEGROUP: self = .precedenceGroup
    case SWIFTIDE_COMPLETION_KIND_STMTLABEL: self = .stmtLabel
    case SWIFTIDE_COMPLETION_KIND_EFFECTSSPECIFIER: self = .effectsSpecifier
    case SWIFTIDE_COMPLETION_KIND_FOREACHPATTERNBEGINNING: self = .forEachPatternBeginning
    case SWIFTIDE_COMPLETION_KIND_TYPEATTRBEGINNING: self = .typeAttrBeginning
    case SWIFTIDE_COMPLETION_KIND_OPTIONALBINDING: self = .optionalBinding
    case SWIFTIDE_COMPLETION_KIND_FOREACHKWIN: self = .forEachKeywordIn
    case SWIFTIDE_COMPLETION_KIND_THENSTMTEXPR: self = .thenStmtExpr
    default: self = .none
    }
  }
}

extension CompletionItem.TypeRelation {
  init(_ crelation: swiftide_api_completion_type_relation_t) {
    switch crelation {
    case SWIFTIDE_COMPLETION_TYPE_RELATION_NOTAPPLICABLE: self = .notApplicable
    case SWIFTIDE_COMPLETION_TYPE_RELATION_UNKNOWN: self = .unknown
    case SWIFTIDE_COMPLETION_TYPE_RELATION_UNRELATED: self = .unrelated
    case SWIFTIDE_COMPLETION_TYPE_RELATION_INVALID: self = .invalid
    case SWIFTIDE_COMPLETION_TYPE_RELATION_CONVERTIBLE: self = .convertible
    case SWIFTIDE_COMPLETION_TYPE_RELATION_IDENTICAL: self = .identical
    default: self = .unknown
    }
  }
}

extension CompletionItem.SemanticContext {
  init(_ ccontext: swiftide_api_completion_semantic_context_t) {
    switch ccontext {
    case SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_NONE: self = .none
    case SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_LOCAL: self = .local
    case SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_CURRENTNOMINAL: self = .currentNominal
    case SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_SUPER: self = .super
    case SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_OUTSIDENOMINAL: self = .outsideNominal
    case SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_CURRENTMODULE: self = .currentModule
    case SWIFTIDE_COMPLETION_SEMANTIC_CONTEXT_OTHERMODULE: self = .otherModule
    default: self = .none
    }
  }
}

extension CompletionItem.PriorityBucket {
  init(_ item: ASTCompletionItem, in session: CompletionSession) {
    if item.completionKind == .unresolvedMember {
      switch item.kind {
      case .enum:
        self = .unresolvedMember_EnumElement
      case .class, .actor, .staticVar:
        self = .unresolvedMember_Var
      case .staticMethod:
        self = .unresolvedMember_Func
      case .constructor:
        self = .unresolvedMember_Constructor
      default:
        self = .unresolvedMember_Other
      }
    } else if item.kind == .constructor {
      self = .constructor
    } else if item.typeRelation(in: session) == .invalid {
      self = .invalidTypeMatch
    } else {
      let skFlair = session.sourcekitd.ideApi.completion_item_get_flair(item.impl)
      if skFlair & SWIFTIDE_COMPLETION_FLAIR_EXPRESSIONSPECIFIC.rawValue != 0
        || skFlair & SWIFTIDE_COMPLETION_FLAIR_SUPERCHAIN.rawValue != 0
      {
        self = .exprSpecific
        return
      }
      // let typeRelation = item.typeRelation(in: CompletionSession)
      let typeMatchPriorityBoost =
        switch item.typeRelation(in: session) {
        case .identical, .convertible: item.kind != .globalVar && item.kind != .keyword
        default: false
        }
      switch (typeMatchPriorityBoost, item.semanticContext(in: session)) {
      case (false, .none):
        self = .noContext_TypeMismatch
      case (false, .otherModule):
        self = .otherModule_TypeMismatch
      case (false, .currentModule):
        self = .thisModule_TypeMismatch
      case (false, .super):
        self = .superClass_TypeMismatch
      case (false, .currentNominal):
        self = .thisClass_TypeMismatch
      case (false, .local):
        self = .local_TypeMismatch
      case (false, .outsideNominal):
        self = .otherClass_TypeMismatch

      case (true, .none):
        self = .noContext_TypeMatch
      case (true, .otherModule):
        self = .otherClass_TypeMatch
      case (true, .currentModule):
        self = .thisModule_TypeMatch
      case (true, .super):
        self = .superClass_TypeMatch
      case (true, .currentNominal):
        self = .thisClass_TypeMatch
      case (true, .local):
        self = .local_TypeMatch
      case (true, .outsideNominal):
        self = .otherClass_TypeMatch
      }
    }
  }
}
