//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Notification from the server containing any diagnostics to show in a given document.
///
/// The publishDiagnostics notification provides the complete set of diagnostics and must be sent
/// whenever the set of active diagnostics change. For example, if a `didChange` notification from
/// the client fixes all of the existing errors, there should be a `publishDiagnostics` notification
/// with an empty `diagnostics = []`.
///
/// There is no guarantee about _when_ the `publishDiagnostics` notification will be sent, and the
/// server is free to not send a notification unless the set of diagnostics has actually changed, or
/// to coalesce the notification across multiple changes in a short period of time.
///
/// - Parameters:
///   - uri: The document in which the diagnostics should be shown.
///   - diagnostics: The complete list of diagnostics in the document, if any.
public struct PublishDiagnosticsNotification: NotificationType, Hashable, Codable {
  public static let method: String = "textDocument/publishDiagnostics"

  /// The document in which the diagnostics should be shown.
  public var uri: DocumentURI

  /// Optional the version number of the document the diagnostics are published for.
  public var version: Int?

  /// The complete list of diagnostics in the document, if any.
  public var diagnostics: [Diagnostic]

  public init(uri: DocumentURI, version: Int? = nil, diagnostics: [Diagnostic]) {
    self.uri = uri
    self.version = version
    self.diagnostics = diagnostics
  }
}
