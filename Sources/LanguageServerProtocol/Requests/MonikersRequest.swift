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

public struct MonikersRequest: TextDocumentRequest {
  public static var method: String = "textDocument/moniker"
  public typealias Response = [Moniker]?

  /// The document in which to lookup the symbol location.
  public var textDocument: TextDocumentIdentifier

  /// The document location at which to lookup symbol information.
  public var position: Position

  public init(textDocument: TextDocumentIdentifier, position: Position) {
    self.textDocument = textDocument
    self.position = position
  }
}

/// Moniker definition to match LSIF 0.5 moniker definition.
public struct Moniker: ResponseType, Hashable {
  /// Moniker uniqueness level to define scope of the moniker.
  public struct UniquenessLevel: RawRepresentable, Codable, Hashable {
    public var rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// The moniker is only unique inside a document
    public static let document = UniquenessLevel(rawValue: "document")

    /// The moniker is unique inside a project for which a dump got created
    public static let project = UniquenessLevel(rawValue: "project")

    /// The moniker is unique inside the group to which a project belongs
    public static let group = UniquenessLevel(rawValue: "group")

    /// The moniker is unique inside the moniker scheme.
    public static let scheme = UniquenessLevel(rawValue: "scheme")

    /// The moniker is globally unique
    public static let global = UniquenessLevel(rawValue: "global")
  }

  /// The moniker kind.
  public struct Kind: RawRepresentable, Codable, Hashable {
    public var rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// The moniker represent a symbol that is imported into a project
    public static let `import` = Kind(rawValue: "import")

    /// The moniker represents a symbol that is exported from a project
    public static let export = Kind(rawValue: "export")

    /// The moniker represents a symbol that is local to a project (e.g. a local
    /// variable of a function, a class not visible outside the project, ...)
    public static let local = Kind(rawValue: "local")
  }



  /// The scheme of the moniker. For example tsc or .Net
  public var scheme: String

  /// The identifier of the moniker. The value is opaque in LSIF however
  /// schema owners are allowed to define the structure if they want.
  public var identifier: String

  /// The scope in which the moniker is unique
  public var unique: UniquenessLevel

  /// The moniker kind if known.
  public var kind: Kind?

  public init(scheme: String, identifier: String, unique: UniquenessLevel, kind: Kind? = nil) {
    self.scheme = scheme
    self.identifier = identifier
    self.unique = unique
    self.kind = kind
  }
}
