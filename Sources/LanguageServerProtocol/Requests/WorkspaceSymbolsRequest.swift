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
  public typealias Response = [SymbolInformation]?

  /// The document in which to lookup the symbol location.
  public var query: String

  public init(query: String) {
    self.query = query
  }
}

public struct SymbolInformation: Hashable, ResponseType {
  public var name: String

  public var kind: SymbolKind

  public var deprecated: Bool?

  public var location: Location

  public var containerName: String?

  public init(name: String,
              kind: SymbolKind,
              deprecated: Bool? = nil,
              location: Location,
              containerName: String? = nil) {
    self.name = name
    self.kind = kind
    self.deprecated = deprecated
    self.location = location
    self.containerName = containerName
  }
}
