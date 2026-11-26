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

@_spi(Testing) import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
import SKOptions
import SKTestSupport
import ToolchainRegistry
import XCTest

final class CanonicalTargetTests: SourceKitLSPTestCase {
  func testPrefersLowestPreference() async throws {
    let file = try DocumentURI(string: "bsm:multi.swift")
    let manager = try await createBuildServerManager(canonicalTargetLayout: [
      file: [
        (target: try target("targetA"), preference: 5),
        (target: try target("targetB"), preference: 1),
        (target: try target("targetC"), preference: 3),
      ]
    ])
    await manager.waitForUpToDateBuildGraph()
    await assertEqual(manager.canonicalTarget(for: file), try target("targetB"))
  }

  func testPreferenceOverridesLexicographicOrder() async throws {
    // `targetA` sorts before `targetB` lexicographically, but the build server prefers `targetB`, so
    // the preference must win over the lexicographic fallback.
    let file = try DocumentURI(string: "bsm:multi.swift")
    let manager = try await createBuildServerManager(canonicalTargetLayout: [
      file: [
        (target: try target("targetA"), preference: 10),
        (target: try target("targetB"), preference: 1),
      ]
    ])
    await manager.waitForUpToDateBuildGraph()
    await assertEqual(manager.canonicalTarget(for: file), try target("targetB"))
  }

  func testTargetsWithoutPreferenceRankAfterThoseWithOne() async throws {
    // `targetA` has no preference and sorts before `targetB` lexicographically, but a target with any
    // preference is preferred over a target without one.
    let file = try DocumentURI(string: "bsm:multi.swift")
    let manager = try await createBuildServerManager(canonicalTargetLayout: [
      file: [
        (target: try target("targetA"), preference: nil),
        (target: try target("targetB"), preference: 100),
      ]
    ])
    await manager.waitForUpToDateBuildGraph()
    await assertEqual(manager.canonicalTarget(for: file), try target("targetB"))
  }

  func testFallsBackToLexicographicOrderWithoutPreferences() async throws {
    // When no target expresses a preference, the smallest target URI is picked deterministically.
    let file = try DocumentURI(string: "bsm:multi.swift")
    let manager = try await createBuildServerManager(canonicalTargetLayout: [
      file: [
        (target: try target("targetB"), preference: nil),
        (target: try target("targetA"), preference: nil),
      ]
    ])
    await manager.waitForUpToDateBuildGraph()
    await assertEqual(manager.canonicalTarget(for: file), try target("targetA"))
  }

  func testTieBreaksLexicographicallyOnEqualPreference() async throws {
    // Equal preferences fall back to the deterministic lexicographic ordering by target URI.
    let file = try DocumentURI(string: "bsm:multi.swift")
    let manager = try await createBuildServerManager(canonicalTargetLayout: [
      file: [
        (target: try target("targetB"), preference: 1),
        (target: try target("targetA"), preference: 1),
      ]
    ])
    await manager.waitForUpToDateBuildGraph()
    await assertEqual(manager.canonicalTarget(for: file), try target("targetA"))
  }

  func testMergesDuplicatePreferencesUsingMinimum() async throws {
    // A file can be reported for the same target more than once. The lowest preference across those
    // reports is used, so `targetA`'s effective preference of 2 beats `targetB`'s 5.
    let file = try DocumentURI(string: "bsm:multi.swift")
    let manager = try await createBuildServerManager(canonicalTargetLayout: [
      file: [
        (target: try target("targetA"), preference: 8),
        (target: try target("targetA"), preference: 2),
        (target: try target("targetB"), preference: 5),
      ]
    ])
    await manager.waitForUpToDateBuildGraph()
    await assertEqual(manager.canonicalTarget(for: file), try target("targetA"))
  }

  func testSingleTarget() async throws {
    let file = try DocumentURI(string: "bsm:single.swift")
    let manager = try await createBuildServerManager(canonicalTargetLayout: [
      file: [(target: try target("targetA"), preference: nil)]
    ])
    await manager.waitForUpToDateBuildGraph()
    await assertEqual(manager.canonicalTarget(for: file), try target("targetA"))
  }

  func testUnknownFileHasNoCanonicalTarget() async throws {
    let known = try DocumentURI(string: "bsm:known.swift")
    let unknown = try DocumentURI(string: "bsm:unknown.swift")
    let manager = try await createBuildServerManager(canonicalTargetLayout: [
      known: [(target: try target("targetA"), preference: 1)]
    ])
    await manager.waitForUpToDateBuildGraph()
    await assertEqual(manager.canonicalTarget(for: unknown), nil)
  }
}

// MARK: - Test helpers

private func target(_ name: String) throws -> BuildTargetIdentifier {
  return BuildTargetIdentifier(uri: try DocumentURI(string: "test://\(name)"))
}

/// The targets a source file belongs to, paired with the `canonicalTargetPreference` the build server
/// reports for each membership (`nil` means the build server expresses no preference for that pairing).
private typealias CanonicalTargetLayout = [DocumentURI: [(target: BuildTargetIdentifier, preference: Int?)]]

/// A build server that reports a fixed `buildTarget/sources` layout in which a file can belong to
/// multiple targets, each carrying a `canonicalTargetPreference`. Used to exercise
/// `BuildServerManager.canonicalTarget(for:)`.
fileprivate actor CanonicalTargetBuildServer: CustomBuildServer {
  let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
  private let layout: CanonicalTargetLayout

  init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
    self.layout = [:]
  }

  init(layout: CanonicalTargetLayout) {
    self.layout = layout
  }

  /// All targets referenced by the layout, in a stable order.
  private var allTargets: [BuildTargetIdentifier] {
    var seen: Set<BuildTargetIdentifier> = []
    var result: [BuildTargetIdentifier] = []
    for memberships in layout.values {
      for membership in memberships where seen.insert(membership.target).inserted {
        result.append(membership.target)
      }
    }
    return result
  }

  func workspaceBuildTargetsRequest(
    _ request: WorkspaceBuildTargetsRequest
  ) -> WorkspaceBuildTargetsResponse {
    return WorkspaceBuildTargetsResponse(
      targets: allTargets.map {
        BuildTarget(id: $0, capabilities: BuildTargetCapabilities(), languageIds: [], dependencies: [])
      }
    )
  }

  func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) -> BuildTargetSourcesResponse {
    var sourcesByTarget: [BuildTargetIdentifier: [SourceItem]] = [:]
    for (uri, memberships) in layout {
      for membership in memberships {
        let data = SourceKitSourceItemData(canonicalTargetPreference: membership.preference)
        sourcesByTarget[membership.target, default: []].append(
          SourceItem(uri: uri, kind: .file, generated: false, dataKind: .sourceKit, data: data.encodeToLSPAny())
        )
      }
    }
    return BuildTargetSourcesResponse(items: sourcesByTarget.map { SourcesItem(target: $0.key, sources: $0.value) })
  }

  func textDocumentSourceKitOptionsRequest(
    _ request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    return nil
  }
}

private func createBuildServerManager(
  canonicalTargetLayout layout: CanonicalTargetLayout
) async throws -> BuildServerManager {
  let dummyPath = URL(fileURLWithPath: "/")
  let spec = BuildServerSpec(
    kind: .injected({ projectRoot, connectionToSourceKitLSP in
      let buildServer = CanonicalTargetBuildServer(layout: layout)
      return LocalConnection(receiverName: "CanonicalTargetBuildServer", handler: buildServer)
    }),
    projectRoot: dummyPath,
    configPath: dummyPath
  )
  return await BuildServerManager(
    buildServerSpec: spec,
    toolchainRegistry: ToolchainRegistry.forTesting,
    options: SourceKitLSPOptions(),
    connectionToClient: DummyBuildServerManagerConnectionToClient(),
    buildServerHooks: BuildServerHooks(),
    createMainFilesProvider: { _, _ in EmptyMainFilesProvider() }
  )
}

/// A `MainFilesProvider` that never reports any main files, for tests that don't exercise header/main
/// file mapping.
private struct EmptyMainFilesProvider: MainFilesProvider {
  func mainFiles(containing uri: DocumentURI, crossLanguage: Bool) async -> Set<DocumentURI> {
    return []
  }
}
