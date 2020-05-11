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
import LanguageServerProtocol

/// The SourceKitOptions request is sent from the client to the server
/// to query for the list of compiler options necessary to compile this file.
public struct SourceKitOptions: RequestType, Hashable {
  public static let method: String = "textDocument/sourceKitOptions"
  public typealias Response = SourceKitOptionsResult

  /// The URI of the document to get options for
  public var uri: URI

  public init(uri: URI) {
    self.uri = uri
  }
}

public struct SourceKitOptionsResult: ResponseType, Hashable {
  /// The compiler options required for the requested file.
  public var options: [String]

  /// The working directory for the compile command.
  public var workingDirectory: String?
}
