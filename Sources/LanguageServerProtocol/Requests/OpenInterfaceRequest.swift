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
  public var moduleName: String

  /// The module group name.
  public var groupNames: [String]

  /// The symbol USR to search for in the generated module interface.
  public var symbolUSR: String?

  public init(textDocument: TextDocumentIdentifier, name: String, symbolUSR: String?) {
    self.textDocument = textDocument
    self.symbolUSR = symbolUSR
    // Stdlib Swift modules are all in the "Swift" module, but their symbols return a module name `Swift.***`.
    let splitName = name.split(separator: ".")
    self.moduleName = String(splitName[0])
    self.groupNames = [String.SubSequence](splitName.dropFirst()).map(String.init)
  }

  /// Name of interface module name with group names appended
  public var name: String {
    if groupNames.count > 0 {
      return "\(self.moduleName).\(self.groupNames.joined(separator: "."))"
    } else {
      return self.moduleName
    }
  }
}

/// The textual output of a module interface.
public struct InterfaceDetails: ResponseType, Hashable {

  public var uri: DocumentURI
  public var position: Position?

  public init(uri: DocumentURI, position: Position?) {
    self.uri = uri
    self.position = position
  }
}
