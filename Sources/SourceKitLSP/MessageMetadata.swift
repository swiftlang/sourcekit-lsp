//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol

/// Metadata stored in `CallHierarchyItem.data` and `TypeHierarchyItem.data` to support
/// incoming/outgoing call and supertype/subtype lookups.
struct HierarchyItemData: Codable, Hashable, LSPAnyCodable {
  var uri: DocumentURI
  var usr: String

  init(uri: DocumentURI, usr: String) {
    self.uri = uri
    self.usr = usr
  }
}

/// Metadata stored in `CompletionItem.data` and `InlayHint.data` at the server level to route
/// resolve requests to the correct language service.
struct ResolveItemData: Codable, Hashable, LSPAnyCodable {
  var uri: DocumentURI

  init(uri: DocumentURI) {
    self.uri = uri
  }
}
