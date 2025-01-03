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

import SourceKitD

#if compiler(>=6)
package import Csourcekitd
#else
import Csourcekitd
#endif

package struct CompletionResult {
  package struct StringEntry {
    let start: UInt32

    package init(start: UInt32) {
      self.start = start
    }
  }

  let kind: sourcekitd_api_uid_t
  let identifier: Int64
  let name: StringEntry
  let description: StringEntry
  let sourceText: StringEntry
  let module: StringEntry?
  let typename: StringEntry
  let textMatchScore: Double
  let semanticScore: Double
  let semanticScoreComponents: StringEntry?
  let priorityBucket: Int32
  let isSystemAndNumBytesToErase: UInt8
  let hasDiagnostic: Bool
  let groupID: Int64

  var isSystem: Bool {
    isSystemAndNumBytesToErase & 0x80 != 0
  }

  var numBytesToErase: Int {
    Int(isSystemAndNumBytesToErase & 0x7F)
  }

  package init(
    kind: sourcekitd_api_uid_t,
    identifier: Int64,
    name: StringEntry,
    description: StringEntry,
    sourceText: StringEntry,
    module: StringEntry?,
    typename: StringEntry,
    textMatchScore: Double,
    semanticScore: Double,
    semanticScoreComponents: StringEntry?,
    priorityBucket: Int32,
    isSystem: Bool,
    numBytesToErase: Int,
    hasDiagnostic: Bool,
    groupID: Int64
  ) {
    self.kind = kind
    self.identifier = identifier
    self.name = name
    self.description = description
    self.sourceText = sourceText
    self.module = module
    self.typename = typename
    self.textMatchScore = textMatchScore
    self.semanticScore = semanticScore
    self.semanticScoreComponents = semanticScoreComponents
    self.priorityBucket = priorityBucket
    precondition(numBytesToErase <= 0x7f, "numBytesToErase exceeds its storage")
    self.isSystemAndNumBytesToErase = UInt8(numBytesToErase) & 0x7f | (isSystem ? 0x80 : 0)
    self.hasDiagnostic = hasDiagnostic
    self.groupID = groupID
  }
}

package struct VariantFunctions: Sendable {
  nonisolated(unsafe) package let rawValue: sourcekitd_api_variant_functions_t
}

package struct CompletionResultsArray {
  let results: UnsafeBufferPointer<CompletionResult>
  let strings: UnsafePointer<CChar>

  init(pointer: UnsafeRawPointer) {
    let numResults = pointer.load(fromByteOffset: 0, as: Int.self)
    let resultStart = MemoryLayout<Int>.size
    self.results = UnsafeBufferPointer<CompletionResult>.init(
      start: (pointer + resultStart).assumingMemoryBound(to: CompletionResult.self),
      count: numResults
    )
    let stringStart = resultStart + results.count * MemoryLayout<CompletionResult>.stride
    self.strings = (pointer + stringStart).assumingMemoryBound(to: CChar.self)
  }

  init(_ variant: sourcekitd_api_variant_t) {
    let ptr = UnsafeRawPointer(bitPattern: UInt(variant.data.1))!
    self.init(pointer: ptr)
  }

  private func cString(_ entry: CompletionResult.StringEntry) -> UnsafePointer<CChar> {
    return strings + Int(entry.start)
  }

  private static func arrayGetCount(_ variant: sourcekitd_api_variant_t) -> Int {
    return CompletionResultsArray(variant).results.count
  }

  private static func arrayGetValue(_ variant: sourcekitd_api_variant_t, _ index: Int) -> sourcekitd_api_variant_t {
    let results = CompletionResultsArray(variant)
    precondition(index < results.results.count)
    return sourcekitd_api_variant_t(
      data: (UInt64(UInt(bitPattern: dictionaryFuncs.rawValue)), variant.data.1, UInt64(index))
    )
  }

  package static let arrayFuncs: VariantFunctions = {
    let sourcekitd = DynamicallyLoadedSourceKitD.relativeToPlugin
    let funcs = sourcekitd.pluginApi.variant_functions_create()!
    sourcekitd.pluginApi.variant_functions_set_get_type(funcs, { _ in SOURCEKITD_API_VARIANT_TYPE_ARRAY })
    sourcekitd.pluginApi.variant_functions_set_array_get_count(funcs, { arrayGetCount($0) })
    sourcekitd.pluginApi.variant_functions_set_array_get_value(funcs, { arrayGetValue($0, $1) })
    return VariantFunctions(rawValue: funcs)
  }()

  static func dictionaryApply(
    _ dict: sourcekitd_api_variant_t,
    _ applier: sourcekitd_api_variant_dictionary_applier_f_t?,
    _ context: UnsafeMutableRawPointer?
  ) -> Bool {
    guard let applier else {
      return true
    }

    struct ApplierReturnedFalse: Error {}

    /// Calls `applier` and if `applier` returns `false`, throw `ApplierReturnedFalse`.
    func apply(
      _ key: sourcekitd_api_uid_t,
      _ value: sourcekitd_api_variant_t,
      _ context: UnsafeMutableRawPointer?
    ) throws {
      if !applier(key, value, context) {
        throw ApplierReturnedFalse()
      }
    }

    let sourcekitd = DynamicallyLoadedSourceKitD.relativeToPlugin
    let keys = sourcekitd.keys

    let results = CompletionResultsArray(dict)
    let index = Int(dict.data.2)

    let result = results.results[index]

    do {
      try apply(keys.kind, sourcekitd_api_variant_t(uid: result.kind), context)
      try apply(keys.identifier, sourcekitd_api_variant_t(result.identifier), context)
      try apply(keys.name, sourcekitd_api_variant_t(results.cString(result.name)), context)
      try apply(keys.description, sourcekitd_api_variant_t(results.cString(result.description)), context)
      try apply(keys.sourceText, sourcekitd_api_variant_t(results.cString(result.sourceText)), context)
      if let module = result.module {
        try apply(keys.moduleName, sourcekitd_api_variant_t(results.cString(module)), context)
      }
      try apply(keys.typeName, sourcekitd_api_variant_t(results.cString(result.typename)), context)
      try apply(keys.priorityBucket, sourcekitd_api_variant_t(Int(result.priorityBucket)), context)
      try apply(keys.textMatchScore, sourcekitd_api_variant_t(result.textMatchScore), context)
      try apply(keys.semanticScore, sourcekitd_api_variant_t(result.semanticScore), context)
      if let semanticScoreComponents = result.semanticScoreComponents {
        try apply(
          keys.semanticScoreComponents,
          sourcekitd_api_variant_t(results.cString(semanticScoreComponents)),
          context
        )
      }
      try apply(keys.isSystem, sourcekitd_api_variant_t(result.isSystem), context)
      if result.numBytesToErase != 0 {
        try apply(keys.numBytesToErase, sourcekitd_api_variant_t(result.numBytesToErase), context)
      }
      try apply(keys.hasDiagnostic, sourcekitd_api_variant_t(result.hasDiagnostic), context)
      if (result.groupID != 0) {
        try apply(keys.groupId, sourcekitd_api_variant_t(result.groupID), context)
      }
    } catch {
      return false
    }
    return true
  }

  static let dictionaryFuncs: VariantFunctions = {
    let sourcekitd = DynamicallyLoadedSourceKitD.relativeToPlugin
    let funcs = sourcekitd.pluginApi.variant_functions_create()!
    sourcekitd.pluginApi.variant_functions_set_get_type(funcs, { _ in SOURCEKITD_API_VARIANT_TYPE_DICTIONARY })
    sourcekitd.pluginApi.variant_functions_set_dictionary_apply(funcs, { dictionaryApply($0, $1, $2) })
    return VariantFunctions(rawValue: funcs)
  }()
}

fileprivate extension sourcekitd_api_variant_t {
  init(scalar: UInt64, type: sourcekitd_api_variant_type_t) {
    self.init(data: (0, scalar, UInt64(type.rawValue)))
  }
  init(_ value: Int) {
    self.init(scalar: UInt64(bitPattern: Int64(value)), type: SOURCEKITD_API_VARIANT_TYPE_INT64)
  }
  init(_ value: Int64) {
    self.init(scalar: UInt64(bitPattern: value), type: SOURCEKITD_API_VARIANT_TYPE_INT64)
  }
  init(_ value: Bool) {
    self.init(scalar: value ? 1 : 0, type: SOURCEKITD_API_VARIANT_TYPE_BOOL)
  }
  init(_ value: Double) {
    self.init(scalar: value.bitPattern, type: SOURCEKITD_API_VARIANT_TYPE_DOUBLE)
  }
  init(_ value: UnsafePointer<CChar>?) {
    self.init(scalar: UInt64(UInt(bitPattern: value)), type: SOURCEKITD_API_VARIANT_TYPE_STRING)
  }
  init(uid: sourcekitd_api_uid_t) {
    self.init(scalar: UInt64(UInt(bitPattern: uid)), type: SOURCEKITD_API_VARIANT_TYPE_UID)
  }
}
