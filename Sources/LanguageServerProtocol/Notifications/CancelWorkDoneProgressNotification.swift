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

public struct CancelWorkDoneProgressNotification: NotificationType {
  public static var method: String = "window/workDoneProgress/cancel"

  public var token: ProgressToken

  public init(token: ProgressToken) {
    self.token = token
  }
}
