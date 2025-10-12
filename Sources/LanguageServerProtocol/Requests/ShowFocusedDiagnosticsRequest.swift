//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Request from the server to the client to show focused diagnostics **(LSP Extension)**
///
/// This request is handled by the client to display focused diagnostic information
/// related to a subset of the source.
///
/// - Parameters:
///   - diagnostics: Array of diagnostics to display
///   - uri: Document URI in which to present the diagnostics
///
/// - Returns: `ShowFocusedDiagnosticsResponse` which indicates the `success` of the request.
///
/// ### LSP Extension
///
/// This request is an extension to LSP supported by SourceKit-LSP.
/// It requires the experimental client capability `workspace/showFocusedDiagnostics` to use.
public struct ShowFocusedDiagnosticsRequest: RequestType {
  public static let method: String = "workspace/showFocusedDiagnostics"
  public typealias Response = ShowFocusedDiagnosticsResponse

  public var diagnostics: [Diagnostic]
  public var uri: DocumentURI

  public init(diagnostics: [Diagnostic], uri: DocumentURI) {
    self.diagnostics = diagnostics
    self.uri = uri
  }
}

/// Response to indicate the `success` of the `ShowFocusedDiagnosticsRequest`
public struct ShowFocusedDiagnosticsResponse: ResponseType {
  public var success: Bool

  public init(success: Bool) {
    self.success = success
  }
}
