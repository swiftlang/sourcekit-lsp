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

public struct WorkspaceSymbolResolveRequest: RequestType {
  public static var method: String = "workspaceSymbol/resolve"
  public typealias Response = WorkspaceSymbol

  public var workspaceSymbol: WorkspaceSymbol

  public init(workspaceSymbol: WorkspaceSymbol) {
    self.workspaceSymbol = workspaceSymbol
  }

  public init(from decoder: Decoder) throws {
    self.workspaceSymbol = try WorkspaceSymbol(from: decoder)
  }

  public func encode(to encoder: Encoder) throws {
    try self.workspaceSymbol.encode(to: encoder)
  }
}
