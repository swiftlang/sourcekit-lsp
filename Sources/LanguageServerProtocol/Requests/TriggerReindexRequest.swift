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

/// Re-index all files open in the SourceKit-LSP server.
///
/// Users should not need to rely on this request. The index should always be updated automatically in the background.
/// Having to invoke this request means there is a bug in SourceKit-LSP's automatic re-indexing. It does, however, offer
/// a workaround to re-index files when such a bug occurs where otherwise there would be no workaround.
///
/// **LSP Extension**
public struct TriggerReindexRequest: LSPRequest {
  public static let method: String = "workspace/triggerReindex"
  public typealias Response = VoidResponse

  public init() {}
}
