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
package import LanguageServerProtocol
package import SKLogging

// MARK: - RequestType

package struct AnyRequestType: CustomLogStringConvertible {
  let request: any RequestType

  package init(request: any RequestType) {
    self.request = request
  }

  package var description: String {
    return """
      \(type(of: request).method)
      \(request.prettyPrintedJSON)
      """
  }

  package var redactedDescription: String {
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

package struct AnyNotificationType: CustomLogStringConvertible {
  let notification: any NotificationType

  package init(notification: any NotificationType) {
    self.notification = notification
  }

  package var description: String {
    return """
      \(type(of: notification).method)
      \(notification.prettyPrintedJSON)
      """
  }

  package var redactedDescription: String {
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

package struct AnyResponseType: CustomLogStringConvertible {
  let response: any ResponseType

  package init(response: any ResponseType) {
    self.response = response
  }

  package var description: String {
    return """
      \(type(of: response))
      \(response.prettyPrintedJSON)
      """
  }

  package var redactedDescription: String {
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
