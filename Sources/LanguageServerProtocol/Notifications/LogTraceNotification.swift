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

/// A notification to log the trace of the server’s execution. The amount and content of these notifications depends on the current trace configuration. If trace is 'off', the server should not send any logTrace notification. If trace is 'messages', the server should not add the 'verbose' field in the LogTraceParams.
///
/// $/logTrace should be used for systematic trace reporting. For single debugging messages, the server should send window/logMessage notifications.
public struct LogTraceNotification: NotificationType, Hashable, Codable {
  public static let method: String = "$/logTrace"

  /// The message to be logged.
  public var message: String

  /// Additional information that can be computed if the `trace` configuration
  /// is set to `'verbose'`
  public var verbose: String?

  public init(message: String, verbose: String?) {
    self.message = message
    self.verbose = verbose
  }
}
