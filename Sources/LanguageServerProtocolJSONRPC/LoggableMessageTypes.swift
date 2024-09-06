//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import SKLogging

// MARK: - RequestType

fileprivate struct AnyRequestType: CustomLogStringConvertible {
  let request: any RequestType

  public var description: String {
    return """
      \(type(of: request).method)
      \(request.prettyPrintedJSON)
      """
  }

  public var redactedDescription: String {
    return """
      \(type(of: request).method)
      \(request.prettyPrintedRedactedJSON)
      """
  }
}

extension RequestType {
  package var forLogging: CustomLogStringConvertibleWrapper {
    return AnyRequestType(request: self).forLogging
  }
}

// MARK: - NotificationType

fileprivate struct AnyNotificationType: CustomLogStringConvertible {
  let notification: any NotificationType

  public var description: String {
    return """
      \(type(of: notification).method)
      \(notification.prettyPrintedJSON)
      """
  }

  public var redactedDescription: String {
    return """
      \(type(of: notification).method)
      \(notification.prettyPrintedRedactedJSON)
      """
  }
}

extension NotificationType {
  package var forLogging: CustomLogStringConvertibleWrapper {
    return AnyNotificationType(notification: self).forLogging
  }
}

// MARK: - ResponseType

fileprivate struct AnyResponseType: CustomLogStringConvertible {
  let response: any ResponseType

  var description: String {
    return """
      \(type(of: response))
      \(response.prettyPrintedJSON)
      """
  }

  var redactedDescription: String {
    return """
      \(type(of: response))
      \(response.prettyPrintedRedactedJSON)
      """
  }
}

extension ResponseType {
  package var forLogging: CustomLogStringConvertibleWrapper {
    return AnyResponseType(response: self).forLogging
  }
}
