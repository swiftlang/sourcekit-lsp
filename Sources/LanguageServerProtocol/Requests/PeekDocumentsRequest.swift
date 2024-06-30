//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct PeekDocumentsRequest: RequestType {
  public static let method: String = "sourcekit-lsp/peekDocuments"
  public typealias Response = PeekDocumentsResponse

  public var uri: DocumentURI?
  public var position: Position?
  public var locations: [DocumentURI]
  public var multiple: Multiple

  public init(
    uri: DocumentURI? = nil,
    position: Position? = nil,
    locations: [DocumentURI],
    multiple: Multiple = .peek
  ) {
    self.uri = uri
    self.position = position
    self.locations = locations
    self.multiple = multiple
  }
}

public struct PeekDocumentsResponse: ResponseType {
  public var success: Bool

  public init(success: Bool) {
    self.success = success
  }
}

public enum Multiple: String, Sendable, Codable {
  case peek
  case goto
  case gotoAndPeek
}
