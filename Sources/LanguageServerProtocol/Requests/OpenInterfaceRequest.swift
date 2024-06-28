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

/// Request a generated interface of a module to display in the IDE.
/// **(LSP Extension)**
public struct OpenGeneratedInterfaceRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/openInterface"
  public typealias Response = GeneratedInterfaceDetails?

  /// The document whose compiler arguments should be used to generate the interface.
  public var textDocument: TextDocumentIdentifier

  /// The module to generate an index for.
  public var moduleName: String

  /// The module group name.
  public var groupName: String?

  /// The symbol USR to search for in the generated module interface.
  public var symbolUSR: String?

  public init(textDocument: TextDocumentIdentifier, name: String, groupName: String?, symbolUSR: String?) {
    self.textDocument = textDocument
    self.symbolUSR = symbolUSR
    self.moduleName = name
    self.groupName = groupName
  }

  /// Name of interface module name with group names appended
  public var name: String {
    if let groupName {
      return "\(self.moduleName).\(groupName.replacing("/", with: "."))"
    }
    return self.moduleName
  }
}

/// The textual output of a module interface.
public struct GeneratedInterfaceDetails: ResponseType, Hashable {

  public var uri: DocumentURI
  public var position: Position?

  public init(uri: DocumentURI, position: Position?) {
    self.uri = uri
    self.position = position
  }
}
