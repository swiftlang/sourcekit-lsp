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

/// Like the language server protocol, a notification to ask the
/// server to exit its process. The server should exit with success
/// code 0 if the shutdown request has been received before;
/// otherwise with error code 1.
public struct OnBuildExitNotification: BSPNotification {
  public static let method: String = "build/exit"

  public init() {}
}
