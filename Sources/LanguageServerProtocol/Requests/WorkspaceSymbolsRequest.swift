//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request for all symbols that match a certain query string.
///
/// This request looks up the canonical occurence of each symbol which has a name that contains the query string.
/// The list of symbol information is returned
///
/// Servers that provide workspace symbol queries should set the `workspaceSymbolProvider` server capability.
///
/// - Parameters:
///   - query: The string that should be looked for in symbols of the workspace.
///
/// - Returns: Information about each symbol with a name that contains the query string
public struct WorkspaceSymbolsRequest: RequestType, Hashable {

  public static let method: String = "workspace/symbol"
  public typealias Response = [WorkspaceSymbolItem]?

  /// The document in which to lookup the symbol location.
  public var query: String

  public init(query: String) {
    self.query = query
  }
}

public enum WorkspaceSymbolItem: ResponseType, Hashable {
  case symbolInformation(SymbolInformation)
  case workspaceSymbol(WorkspaceSymbol)

  public init(from decoder: Decoder) throws {
    if let symbolInformation = try? SymbolInformation(from: decoder) {
      self = .symbolInformation(symbolInformation)
    } else if let workspaceSymbol = try? WorkspaceSymbol(from: decoder) {
      self = .workspaceSymbol(workspaceSymbol)
    } else {
      let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected SymbolInformation or WorkspaceSymbol")
      throw DecodingError.dataCorrupted(context)
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .symbolInformation(let symbolInformation):
      try symbolInformation.encode(to: encoder)
    case .workspaceSymbol(let workspaceSymbol):
      try workspaceSymbol.encode(to: encoder)
    }
  }
}

public struct SymbolInformation: Hashable, ResponseType {
  public var name: String

  public var kind: SymbolKind

  public var tags: [SymbolTag]?

  public var deprecated: Bool?

  public var location: Location

  public var containerName: String?

  public init(name: String,
              kind: SymbolKind,
              tags: [SymbolTag]? = nil,
              deprecated: Bool? = nil,
              location: Location,
              containerName: String? = nil) {
    self.name = name
    self.kind = kind
    self.tags = tags
    self.deprecated = deprecated
    self.location = location
    self.containerName = containerName
  }
}

/// A special workspace symbol that supports locations without a range
public struct WorkspaceSymbol: ResponseType, Hashable {
  public enum WorkspaceSymbolLocation: Codable, Hashable {
    public struct URI: Codable, Hashable {
      public var uri: DocumentURI

      public init(uri: DocumentURI) {
        self.uri = uri
      }
    }

    case location(Location)
    case uri(URI)

    public init(from decoder: Decoder) throws {
      if let location = try? Location(from: decoder) {
        self = .location(location)
      } else if let uri = try? WorkspaceSymbolLocation.URI(from: decoder) {
        self = .uri(uri)
      } else {
        let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Location or object containing a URI")
        throw DecodingError.dataCorrupted(context)
      }
    }

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .location(let location):
        try location.encode(to: encoder)
      case .uri(let uri):
        try uri.encode(to: encoder)
      }
    }
  }

  /// The name of this symbol.
  public var name: String

  /// The kind of this symbol.
  public var kind: SymbolKind

  /// Tags for this completion item.
  public var tags: [SymbolTag]?

  /// The name of the symbol containing this symbol. This information is for
  /// user interface purposes (e.g. to render a qualifier in the user interface
  /// if necessary). It can't be used to re-infer a hierarchy for the document
  /// symbols.
  public var containerName: String?

  /// The location of this symbol. Whether a server is allowed to
  /// return a location without a range depends on the client
  /// capability `workspace.symbol.resolveSupport`.
  ///
  /// See also `SymbolInformation.location`.
  public var location: WorkspaceSymbolLocation

  /// A data entry field that is preserved on a workspace symbol between a
  /// workspace symbol request and a workspace symbol resolve request.
  public var data: LSPAny?

  public init(name: String, kind: SymbolKind, tags: [SymbolTag]? = nil, containerName: String? = nil, location: WorkspaceSymbolLocation, data: LSPAny? = nil) {
    self.name = name
    self.kind = kind
    self.tags = tags
    self.containerName = containerName
    self.location = location
    self.data = data
  }
}
