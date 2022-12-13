//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request a textual interface of a module to display in the IDE.
/// **(LSP Extension)**
public struct OpenInterfaceRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/openInterface"
  public typealias Response = InterfaceDetails?

  /// The document whose compiler arguments should be used to generate the interface.
  public var textDocument: TextDocumentIdentifier

  /// The module to generate an index for.
  public var name: String

  public init(textDocument: TextDocumentIdentifier, name: String) {
    self.textDocument = textDocument
    self.name = name
  }
}

/// The textual output of a module interface.
public struct InterfaceDetails: ResponseType, Hashable {

  public var uri: DocumentURI

  public init(uri: DocumentURI) {
    self.uri = uri
  }
}
