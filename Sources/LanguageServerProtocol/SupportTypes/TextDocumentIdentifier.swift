//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Unique identifier for a document.
public struct TextDocumentIdentifier: Hashable, Codable {

  /// A URI that uniquely identifies the document.
  public var uri: DocumentURI

  public init(_ uri: DocumentURI) {
    self.uri = uri
  }
}

extension TextDocumentIdentifier: LSPAnyCodable {
  public init?(fromLSPDictionary dictionary: [String : LSPAny]) {
    guard case .string(let uriString)? = dictionary[CodingKeys.uri.stringValue] else {
      return nil
    }
    self.uri = DocumentURI(string: uriString)
  }

  public func encodeToLSPAny() -> LSPAny {
    return .dictionary([
      CodingKeys.uri.stringValue: .string(uri.stringValue)
    ])
  }
}
