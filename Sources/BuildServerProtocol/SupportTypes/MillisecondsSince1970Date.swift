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

public import Foundation
public import LanguageServerProtocol

public struct MillisecondsSince1970Date: CustomCodableWrapper {
  public var wrappedValue: Date

  public init(wrappedValue: Date) {
    self.wrappedValue = wrappedValue
  }

  public init(from decoder: any Decoder) throws {
    let millisecondsSince1970 = try decoder.singleValueContainer().decode(Int64.self)
    self.wrappedValue = Date(timeIntervalSince1970: Double(millisecondsSince1970) / 1_000)
  }

  public func encode(to encoder: any Encoder) throws {
    let millisecondsSince1970 = Int64((wrappedValue.timeIntervalSince1970 * 1_000).rounded())
    var container = encoder.singleValueContainer()
    try container.encode(millisecondsSince1970)
  }
}
