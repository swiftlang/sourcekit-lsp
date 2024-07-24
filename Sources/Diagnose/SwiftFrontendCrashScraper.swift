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

import BuildSystemIntegration
import Foundation

struct SwiftFrontendCrashScraper {
  /// Information we care about in a `.ips` crash report.
  private struct IpsCrashReport: Decodable {
    struct Asi: Decodable {
      let swiftFrontend: [String]
      enum CodingKeys: CodingKey {
        case swiftFrontend

        var stringValue: String {
          switch self {
          case .swiftFrontend: "swift-frontend"
          }
        }
      }
    }
    let procLaunch: Date
    let asi: Asi
  }

  struct SwiftFrontendCrash {
    let date: Date
    let swiftFrontend: URL
    let frontendArgs: [String]
  }

  private var directoriesToScanForCrashReports: [String]

  init(directoriesToScanForCrashReports: [String]) {
    self.directoriesToScanForCrashReports = directoriesToScanForCrashReports
  }

  private func crashReports() -> [URL] {
    var crashReports: [URL] = []
    for directoryToScan in directoriesToScanForCrashReports {
      let diagnosticReports = URL(fileURLWithPath: (directoryToScan as NSString).expandingTildeInPath)
      let enumerator = FileManager.default.enumerator(at: diagnosticReports, includingPropertiesForKeys: nil)
      while let fileUrl = enumerator?.nextObject() as? URL {
        if fileUrl.lastPathComponent.hasPrefix("swift-frontend"), fileUrl.pathExtension == "ips" {
          crashReports.append(fileUrl)
        }
      }
    }
    return crashReports
  }

  /// Find `swift-frontend` crashes
  func findSwiftFrontendCrashes() -> [SwiftFrontendCrash] {
    return crashReports().compactMap { (crashReportUrl) -> SwiftFrontendCrash? in
      guard let fileContents = try? String(contentsOf: crashReportUrl, encoding: .utf8) else {
        return nil
      }
      // The first line contains some summary data that we're not interested in. Remove it
      guard let firstNewline = fileContents.firstIndex(of: "\n") else {
        return nil
      }
      let interestingString = fileContents[firstNewline...]
      let dateFormatter = DateFormatter()
      dateFormatter.timeZone = NSTimeZone.local
      dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS Z"
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .formatted(dateFormatter)
      guard let decoded = try? decoder.decode(IpsCrashReport.self, from: interestingString.data(using: .utf8)!) else {
        return nil
      }

      let commandLineString = decoded.asi.swiftFrontend
        .compactMap { (entry) -> Substring? in
          guard let range = entry.firstRange(of: "Program arguments: ") else {
            return nil
          }
          return entry[range.upperBound...]
        }
        .first

      guard let commandLineString else {
        return nil
      }

      let commandLine = splitShellEscapedCommand(String(commandLineString))
      guard let swiftFrontendPath = commandLine.first else {
        return nil
      }
      let swiftFrontendUrl = URL(fileURLWithPath: swiftFrontendPath)

      return SwiftFrontendCrash(
        date: decoded.procLaunch,
        swiftFrontend: swiftFrontendUrl,
        frontendArgs: Array(commandLine.dropFirst())
      )
    }
  }
}
