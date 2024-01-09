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
import LSPLogging
import LanguageServerProtocol

fileprivate extension Encodable {
  var prettyPrintJSON: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting.insert(.prettyPrinted)
    encoder.outputFormatting.insert(.sortedKeys)
    guard let data = try? encoder.encode(self) else {
      return "\(self)"
    }
    guard let string = String(data: data, encoding: .utf8) else {
      return "\(self)"
    }
    // Don't escape '/'. Most JSON readers don't need it escaped and it makes
    // paths a lot easier to read and copy-paste.
    return string.replacingOccurrences(of: "\\/", with: "/")
  }
}

// MARK: - RequestType

fileprivate struct AnyRequestType: CustomLogStringConvertible {
  let request: any RequestType

  public var description: String {
    return """
      \(type(of: request).method)
      \(request.prettyPrintJSON)
      """
  }

  public var redactedDescription: String {
    return "\(type(of: request).method)"
  }
}

extension RequestType {
  public var forLogging: CustomLogStringConvertibleWrapper {
    return AnyRequestType(request: self).forLogging
  }
}

// MARK: - NotificationType

fileprivate struct AnyNotificationType: CustomLogStringConvertible {
  let notification: any NotificationType

  public var description: String {
    return """
      \(type(of: notification).method)
      \(notification.prettyPrintJSON)
      """
  }

  public var redactedDescription: String {
    return "\(type(of: notification).method)"
  }
}

extension NotificationType {
  public var forLogging: CustomLogStringConvertibleWrapper {
    return AnyNotificationType(notification: self).forLogging
  }
}

// MARK: - ResponseType

fileprivate struct AnyResponseType: CustomLogStringConvertible {
  let response: any ResponseType

  var description: String {
    return """
      \(type(of: response))
      \(response.prettyPrintJSON)
      """
  }

  var redactedDescription: String {
    return """
      \(type(of: response))
      """
  }
}

extension ResponseType {
  public var forLogging: CustomLogStringConvertibleWrapper {
    return AnyResponseType(response: self).forLogging
  }
}
