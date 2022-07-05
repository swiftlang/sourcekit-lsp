//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The request is sent from the client to the server to resolve the supertypes for
/// a given call hierarchy item. It is only issued if a server registers for the
/// `textDocument/prepareTypeHierarchy` request.
public struct TypeHierarchySupertypesRequest: RequestType {
  public static let method: String = "typeHierarchy/supertypes"
  public typealias Response = [TypeHierarchyItem]?

  public var item: TypeHierarchyItem

  public init(item: TypeHierarchyItem) {
    self.item = item
  }
}
