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

import Foundation
import LanguageServerProtocolExtensions
import SwiftExtensions
import TSCExtensions

#if os(macOS)
import struct TSCBasic.RelativePath
#endif

/// A helper type for decoding the Info.plist or ToolchainInfo.plist file from an .xctoolchain.
package struct XCToolchainPlist {

  /// The toolchain identifier e.g. "com.apple.dt.toolchain.XcodeDefault".
  package var identifier: String

  /// The toolchain's human-readable name.
  package var displayName: String?

  package init(identifier: String, displayName: String? = nil) {
    self.identifier = identifier
    self.displayName = displayName
  }
}

extension XCToolchainPlist {
  enum Error: Swift.Error {
    case unsupportedPlatform
    case notFound(missingPlistPath: URL?)
  }

  /// Returns the plist contents from the xctoolchain in the given directory, either Info.plist or
  /// ToolchainInfo.plist.
  ///
  /// - parameter path: The directory to search.
  /// - throws: If there is not plist file or it cannot be read.
  init(fromDirectory path: URL) throws {
    #if os(macOS)
    let plistNames = [
      try RelativePath(validating: "ToolchainInfo.plist"),  // Xcode
      try RelativePath(validating: "Info.plist"),  // Swift.org
    ]

    var missingPlistPath: URL?
    for plistPath in plistNames.lazy.map({ path.appending($0) }) {
      if FileManager.default.isFile(at: plistPath) {
        try self.init(path: plistPath)
        return
      }

      missingPlistPath = plistPath
    }

    throw Error.notFound(missingPlistPath: missingPlistPath)
    #else
    throw Error.unsupportedPlatform
    #endif
  }

  /// Returns the plist contents from the xctoolchain at `path`.
  ///
  /// - parameter path: The directory to search.
  init(path: URL) throws {
    #if os(macOS)
    let data = try Data(contentsOf: path)
    let decoder = PropertyListDecoder()
    var format = PropertyListSerialization.PropertyListFormat.binary
    self = try decoder.decode(XCToolchainPlist.self, from: data, format: &format)
    #else
    throw Error.unsupportedPlatform
    #endif
  }
}

extension XCToolchainPlist: Codable {

  private enum CodingKeys: String, CodingKey {
    case Identifier
    case CFBundleIdentifier
    case DisplayName
  }

  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let identifier = try container.decodeIfPresent(String.self, forKey: .Identifier) {
      self.identifier = identifier
    } else {
      self.identifier = try container.decode(String.self, forKey: .CFBundleIdentifier)
    }
    self.displayName = try container.decodeIfPresent(String.self, forKey: .DisplayName)
  }

  /// Encode the info plist.
  ///
  /// For testing purposes only.
  package func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if identifier.starts(with: "com.apple") {
      try container.encode(identifier, forKey: .Identifier)
    } else {
      try container.encode(identifier, forKey: .CFBundleIdentifier)
    }
    try container.encodeIfPresent(displayName, forKey: .DisplayName)
  }
}
