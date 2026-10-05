//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import SKUtilities
import SourceKitLSP
import SwiftLanguageService
import SwiftParser
import ToolchainRegistry
import XCTest

final class PackageManifestFeatureSupportTests: SourceKitLSPTestCase {
  private let supportedFeatures = SupportedSwiftFeatures(
    upcoming: [
      SupportedSwiftFeature(name: "ConciseMagicFile", kind: .upcoming, enabledIn: SwiftVersion(6, 0)),
      SupportedSwiftFeature(name: "ExistentialAny", kind: .upcoming, enabledIn: nil),
      SupportedSwiftFeature(name: "InternalImportsByDefault", kind: .upcoming, enabledIn: nil),
    ],
    experimental: [
      SupportedSwiftFeature(name: "Embedded", kind: .experimental, enabledIn: nil)
    ]
  )

  func testDiagnosticsForPackageManifestFeatures() throws {
    let diagnostics = diagnostics(
      """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
        name: "Pkg",
        swiftSettings: [
          .enableUpcomingFeature("ExistentialAny"),
          .enableUpcomingFeature("ExistentialAy"),
          .enableUpcomingFeature("Embedded"),
          .enableUpcomingFeature("ConciseMagicFile"),
          .enableExperimentalFeature("Embedded"),
          .enableExperimentalFeature("Embeddid"),
          .enableExperimentalFeature("ExistentialAny"), 
          .enableUpcomingFeature("SomethingCompletelyUnknown"),
          .define("ExistentialAy")
        ]
      )
      """
    )

    XCTAssertFalse(
      diagnostics.contains {
        $0.message.contains("ExistentialAny") && !$0.message.contains("ExistentialAy")
          && !$0.message.contains("experimental")
      }
    )
    XCTAssert(
      diagnostics.contains {
        $0.message == "'ExistentialAy' is not a recognized upcoming feature; did you mean 'ExistentialAny'?"
      }
    )
    XCTAssert(
      diagnostics.contains {
        $0.message == "'Embedded' is not a recognized upcoming feature; use enableExperimentalFeature instead"
      }
    )

    XCTAssert(
      diagnostics.contains {
        $0.message == "'ExistentialAny' is not a recognized experimental feature; use enableUpcomingFeature instead"
      }
    )

    XCTAssert(
      diagnostics.contains {
        $0.message == "'SomethingCompletelyUnknown' is not a recognized upcoming feature"
      }
    )

    XCTAssert(diagnostics.contains { $0.message == "'ConciseMagicFile' is already enabled in Swift 6.0" })
    XCTAssert(
      diagnostics.contains {
        $0.message == "'Embeddid' is not a recognized experimental feature; did you mean 'Embedded'?"
      }
    )
    XCTAssertFalse(diagnostics.contains { $0.message.contains(".define") })
  }

  func testDiagnosticsDoNotApplyOutsidePackageManifest() throws {
    let diagnostics = diagnostics(
      """
      func test() {
        enableUpcomingFeature("ExistentialAy")
        _ = "ExistentialAy"
      }
      """,
      fileName: "File.swift"
    )

    XCTAssertEqual(diagnostics, [])
  }

  func testCompletionForPackageManifestFeatures() throws {
    let upcoming = try XCTUnwrap(
      completions(
        """
        let package = Package(
          name: "Pkg",
          swiftSettings: [
            .enableUpcomingFeature("1️⃣")
          ]
        )
        """
      )
    )
    XCTAssert(upcoming.items.contains { $0.label == "ExistentialAny" })
    XCTAssert(upcoming.items.contains { $0.label == "InternalImportsByDefault" })
    XCTAssertFalse(upcoming.items.contains { $0.label == "Embedded" })

    let experimental = try XCTUnwrap(
      completions(
        """
        let package = Package(
          name: "Pkg",
          swiftSettings: [
            .enableExperimentalFeature("1️⃣")
          ]
        )
        """
      )
    )
    XCTAssertEqual(experimental.items.map(\.label), ["Embedded"])

    let partial = try XCTUnwrap(
      completions(
        """
        let package = Package(
          name: "Pkg",
          swiftSettings: [
            .enableUpcomingFeature("ExistentialA1️⃣")
          ]
        )
        """
      )
    )
    XCTAssertEqual(partial.items.map(\.label), ["ExistentialAny"])
    XCTAssertEqual(
      partial.items.first?.textEdit,
      // FIX: Change 31 to 28, and 43 to 40 to match the exact utf16 string indices
      .textEdit(
        TextEdit(
          range: Position(line: 3, utf16index: 28)..<Position(line: 3, utf16index: 40),
          newText: "ExistentialAny"
        )
      )
    )

    let partialExperimental = try XCTUnwrap(
      completions(
        """
        let package = Package(
          name: "Pkg",
          swiftSettings: [
            .enableExperimentalFeature("Emb1️⃣")
          ]
        )
        """
      )
    )
    XCTAssertEqual(partialExperimental.items.map(\.label), ["Embedded"])

    XCTAssertEqual(
      partialExperimental.items.first?.textEdit,
      .textEdit(
        TextEdit(range: Position(line: 3, utf16index: 32)..<Position(line: 3, utf16index: 35), newText: "Embedded")
      )
    )
  }

  func testCompletionDoesNotApplyToUnrelatedStrings() throws {
    let completion = try completions(
      """
      let value = "1️⃣"
      """
    )

    XCTAssertNil(completion)
  }

  func testDiagnosticsApplyToVersionedPackageManifest() throws {
    let diagnostics = diagnostics(
      """
      .enableUpcomingFeature("ExistentialAy")
      """,
      fileName: "Package@swift-6.0.swift"
    )

    XCTAssert(
      diagnostics.contains {
        $0.message == "'ExistentialAy' is not a recognized upcoming feature; did you mean 'ExistentialAny'?"
      }
    )
  }

  func testUpcomingFeatureDoesNotDiagnoseWithoutLanguageVersion() throws {
    let diagnostics = diagnostics(
      """
      .enableUpcomingFeature("ConciseMagicFile")
      """,
      swiftLanguageVersion: nil
    )

    XCTAssertFalse(
      diagnostics.contains {
        $0.message.contains("'ConciseMagicFile' is already enabled")
      }
    )
  }

  private func diagnostics(
    _ text: String,
    fileName: String = "Package.swift",
    swiftLanguageVersion: SwiftVersion? = SwiftVersion(6, 0)
  ) -> [Diagnostic] {
    let snapshot = snapshot(text, fileName: fileName)
    return PackageManifestFeatureSupport.diagnostics(
      in: snapshot,
      syntaxTree: Parser.parse(source: text),
      supportedFeatures: supportedFeatures,
      swiftLanguageVersion: swiftLanguageVersion
    )
  }

  private func completions(_ markedText: String) throws -> CompletionList? {
    let (markers, text) = extractMarkers(markedText)
    let snapshot = snapshot(text, fileName: "Package.swift")
    return PackageManifestFeatureSupport.completion(
      in: snapshot,
      syntaxTree: Parser.parse(source: text),
      position: snapshot.position(of: try XCTUnwrap(markers["1️⃣"])),
      supportedFeatures: supportedFeatures
    )
  }

  private func snapshot(_ text: String, fileName: String) -> DocumentSnapshot {
    DocumentSnapshot(
      uri: DocumentURI(URL(fileURLWithPath: "/tmp/\(fileName)")),
      language: .swift,
      version: 0,
      lineTable: LineTable(text),
      origin: .openDocument
    )
  }
}
