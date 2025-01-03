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
import SourceKitD
import SwiftSourceKitPluginCommon

struct CompletionResultsArrayBuilder {
  private let bufferKind: UInt64
  private var results: [CompletionResult] = []
  private var stringTable: [String: Int] = [:]
  private var nextString: Int = 0
  private let startLoc: Position

  init(bufferKind: UInt64, numResults: Int, session: CompletionSession) {
    self.bufferKind = bufferKind
    self.results.reserveCapacity(numResults)
    self.stringTable.reserveCapacity(numResults * 3)
    self.startLoc = session.location.position
  }

  private mutating func addString(_ str: String) -> CompletionResult.StringEntry {
    if let value = stringTable[str] {
      return CompletionResult.StringEntry(start: UInt32(value))
    } else {
      let value = nextString
      precondition(value < Int(UInt32.max))
      nextString += str.utf8.count + 1

      stringTable[str] = value
      return CompletionResult.StringEntry(start: UInt32(value))
    }
  }

  private mutating func addString(_ str: String?) -> CompletionResult.StringEntry? {
    guard let str else {
      return nil
    }
    return addString(str) as CompletionResult.StringEntry
  }

  mutating func add(_ item: CompletionItem, includeSemanticComponents: Bool, sourcekitd: SourceKitD) {
    let result = CompletionResult(
      kind: sourcekitd_api_uid_t(item.kind, sourcekitd: sourcekitd),
      identifier: item.id.opaqueValue,
      name: addString(item.filterText),
      description: addString(item.label),
      sourceText: addString(item.textEdit.newText),
      module: addString(item.module),
      typename: addString(item.typeName ?? ""),
      textMatchScore: item.textMatchScore,
      semanticScore: item.semanticScore,
      semanticScoreComponents: includeSemanticComponents ? addString(item.semanticClassification?.asBase64) : nil,
      priorityBucket: Int32(item.priorityBucket.rawValue),
      isSystem: item.isSystem,
      numBytesToErase: item.numBytesToErase(from: startLoc),
      hasDiagnostic: item.hasDiagnostic,
      groupID: Int64(item.groupID ?? 0)
    )
    results.append(result)
  }

  func bytes() -> [UInt8] {
    let capacity =
      MemoryLayout<UInt64>.size  // kind
      + MemoryLayout<Int>.size  // numResults
      + results.count * MemoryLayout<CompletionResult>.stride + nextString

    return Array<UInt8>(unsafeUninitializedCapacity: capacity) {
      (bytes: inout UnsafeMutableBufferPointer<UInt8>, size: inout Int) in
      size = capacity
      var cursor = UnsafeMutableRawBufferPointer(bytes)
      cursor.storeBytes(of: self.bufferKind, toByteOffset: 0, as: UInt64.self)
      cursor = UnsafeMutableRawBufferPointer(rebasing: cursor[MemoryLayout<UInt64>.size...])
      cursor.storeBytes(of: self.results.count, toByteOffset: 0, as: Int.self)
      cursor = UnsafeMutableRawBufferPointer(rebasing: cursor[MemoryLayout<Int>.size...])
      self.results.withUnsafeBytes { raw in
        cursor.copyMemory(from: raw)
        cursor = UnsafeMutableRawBufferPointer(rebasing: cursor[raw.count...])
      }
      for (str, startOffset) in stringTable {
        let slice = UnsafeMutableRawBufferPointer(rebasing: cursor[startOffset...])
        str.utf8CString.withUnsafeBytes { raw in
          slice.copyMemory(from: raw)
        }
      }
    }
  }
}

extension CompletionItem {
  func numBytesToErase(from: Position) -> Int {
    guard textEdit.range.lowerBound.line == from.line else {
      assertionFailure("unsupported multi-line completion edit start \(from) vs \(textEdit)")
      return 0
    }
    return from.utf8Column - textEdit.range.lowerBound.utf8Column
  }
}

extension SemanticClassification {
  var asBase64: String {
    return Data(self.byteRepresentation()).base64EncodedString()
  }
}
