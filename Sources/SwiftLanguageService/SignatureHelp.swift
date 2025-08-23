//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
package import LanguageServerProtocol
import SKLogging
import SourceKitD
import SourceKitLSP
import SwiftBasicFormat

fileprivate extension String {
  func utf16Offset(of utf8Offset: Int, callerFile: StaticString = #fileID, callerLine: UInt = #line) -> Int {
    guard
      let stringIndex = self.utf8.index(self.startIndex, offsetBy: utf8Offset, limitedBy: self.endIndex)
    else {
      logger.fault(
        """
        UTF-8 offset is past the end of the string while getting UTF-16 offset of \(utf8Offset) \
        (\(callerFile, privacy: .public):\(callerLine, privacy: .public))
        """
      )
      return self.utf16.count
    }
    return self.utf16.distance(from: self.startIndex, to: stringIndex)
  }
}

fileprivate extension ParameterInformation {
  init?(_ parameter: SKDResponseDictionary, _ signatureLabel: String, _ keys: sourcekitd_api_keys) {
    guard let nameOffset = parameter[keys.nameOffset] as Int?,
      let nameLength = parameter[keys.nameLength] as Int?
    else {
      return nil
    }

    let documentation: StringOrMarkupContent? =
      if let docComment: String = parameter[keys.docComment] {
        .markupContent(MarkupContent(kind: .markdown, value: docComment))
      } else {
        nil
      }

    let labelStart = signatureLabel.utf16Offset(of: nameOffset)
    let labelEnd = signatureLabel.utf16Offset(of: nameOffset + nameLength)

    self.init(
      label: .offsets(start: labelStart, end: labelEnd),
      documentation: documentation
    )
  }
}

fileprivate extension SignatureInformation {
  init?(_ signature: SKDResponseDictionary, _ keys: sourcekitd_api_keys) {
    guard let label = signature[keys.name] as String?,
      let skParameters = signature[keys.parameters] as SKDResponseArray?
    else {
      return nil
    }

    let activeParameter = signature[keys.activeParameter] as Int?
    let parameters = skParameters.compactMap { ParameterInformation($0, label, keys) }

    let documentation: StringOrMarkupContent? =
      if let docComment: String = signature[keys.docComment] {
        .markupContent(MarkupContent(kind: .markdown, value: docComment))
      } else {
        nil
      }

    self.init(
      label: label,
      documentation: documentation,
      parameters: parameters,
      activeParameter: activeParameter
    )
  }
}

fileprivate extension SignatureHelp {
  init?(_ dict: SKDResponseDictionary, _ keys: sourcekitd_api_keys) {
    guard let skSignatures = dict[keys.signatures] as SKDResponseArray?,
      let activeSignature = dict[keys.activeSignature] as Int?
    else {
      return nil
    }

    let signatures = skSignatures.compactMap { SignatureInformation($0, keys) }

    guard !signatures.isEmpty else {
      return nil
    }

    self.init(
      signatures: signatures,
      activeSignature: activeSignature,
      activeParameter: signatures[activeSignature].activeParameter
    )
  }
}

extension SwiftLanguageService {
  package func signatureHelp(_ req: SignatureHelpRequest) async throws -> SignatureHelp? {
    let snapshot = try documentManager.latestSnapshot(req.textDocument.uri)

    let adjustedPosition = await adjustPositionToStartOfArgument(req.position, in: snapshot)

    let compileCommand = await compileCommand(for: snapshot.uri, fallbackAfterTimeout: false)

    let skreq = sourcekitd.dictionary([
      keys.offset: snapshot.utf8Offset(of: adjustedPosition),
      keys.sourceFile: snapshot.uri.sourcekitdSourceFile,
      keys.primaryFile: snapshot.uri.primaryFile?.pseudoPath,
      keys.compilerArgs: compileCommand?.compilerArgs as [SKDRequestValue]?,
    ])

    let dict = try await send(sourcekitdRequest: \.signatureHelp, skreq, snapshot: snapshot)

    return SignatureHelp(dict, keys)
  }
}
