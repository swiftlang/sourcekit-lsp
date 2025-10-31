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

@_spi(Testing) import BuildServerIntegration
@_spi(SourceKitLSP) import BuildServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocol
@_spi(SourceKitLSP) import LanguageServerProtocolExtensions
@_spi(SourceKitLSP) import LanguageServerProtocolTransport
@_spi(SourceKitLSP) import SKLogging
import SKOptions
import SKTestSupport
import SwiftExtensions
import TSCBasic
import ToolchainRegistry
import XCTest

fileprivate actor TestBuildServer: CustomBuildServer {
  let inProgressRequestsTracker = CustomBuildServerInProgressRequestTracker()
  private let connectionToSourceKitLSP: any Connection
  private var buildSettingsByFile: [DocumentURI: TextDocumentSourceKitOptionsResponse] = [:]

  func setBuildSettings(for uri: DocumentURI, to buildSettings: TextDocumentSourceKitOptionsResponse?) {
    buildSettingsByFile[uri] = buildSettings
    connectionToSourceKitLSP.send(OnBuildTargetDidChangeNotification(changes: nil))
  }

  init(projectRoot: URL, connectionToSourceKitLSP: any Connection) {
    self.connectionToSourceKitLSP = connectionToSourceKitLSP
  }

  func buildTargetSourcesRequest(_ request: BuildTargetSourcesRequest) -> BuildTargetSourcesResponse {
    return dummyTargetSourcesResponse(files: buildSettingsByFile.keys)
  }

  func textDocumentSourceKitOptionsRequest(
    _ request: TextDocumentSourceKitOptionsRequest
  ) async throws -> TextDocumentSourceKitOptionsResponse? {
    return buildSettingsByFile[request.textDocument.uri]
  }
}

fileprivate extension BuildServerManager {
  func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) async {
    handle(OnBuildTargetDidChangeNotification(changes: nil))
  }
}

private func createBuildServerManager(
  mainFilesProvider: some MainFilesProvider
) async throws -> (manager: BuildServerManager, buildServer: TestBuildServer) {
  let dummyPath = URL(fileURLWithPath: "/")
  let testBuildServer = ThreadSafeBox<TestBuildServer?>(initialValue: nil)
  let spec = BuildServerSpec(
    kind: .injected({ projectRoot, connectionToSourceKitLSP in
      assert(testBuildServer.value == nil, "Build server injector hook can only create a single TestBuildServer")
      let buildServer = TestBuildServer(projectRoot: projectRoot, connectionToSourceKitLSP: connectionToSourceKitLSP)
      testBuildServer.value = buildServer
      return LocalConnection(receiverName: "TestBuildServer", handler: buildServer)
    }),
    projectRoot: dummyPath,
    configPath: dummyPath
  )

  let manager = await BuildServerManager(
    buildServerSpec: spec,
    toolchainRegistry: ToolchainRegistry.forTesting,
    options: SourceKitLSPOptions(),
    connectionToClient: DummyBuildServerManagerConnectionToClient(),
    buildServerHooks: BuildServerHooks(),
    createMainFilesProvider: { _, _ in mainFilesProvider }
  )
  let buildServer = try unwrap(testBuildServer.value)
  return (manager, buildServer)
}

final class BuildServerManagerTests: SourceKitLSPTestCase {
  func testMainFiles() async throws {
    let a = try DocumentURI(string: "bsm:a")
    let b = try DocumentURI(string: "bsm:b")
    let c = try DocumentURI(string: "bsm:c")
    let d = try DocumentURI(string: "bsm:d")

    let mainFiles = ManualMainFilesProvider(
      [
        a: [c],
        b: [c, d],
        c: [c],
        d: [d],
      ]
    )

    let (manager, _) = try await createBuildServerManager(mainFilesProvider: mainFiles)

    await assertEqual(manager.cachedMainFile(for: a), nil)
    await assertEqual(manager.cachedMainFile(for: b), nil)
    await assertEqual(manager.cachedMainFile(for: c), nil)
    await assertEqual(manager.cachedMainFile(for: d), nil)

    await manager.registerForChangeNotifications(for: a, language: .c)
    await manager.registerForChangeNotifications(for: b, language: .c)
    await manager.registerForChangeNotifications(for: c, language: .c)
    await manager.registerForChangeNotifications(for: d, language: .c)
    await assertEqual(manager.cachedMainFile(for: a), c)
    let bMain = await manager.cachedMainFile(for: b)
    assertContains([c, d], bMain)
    await assertEqual(manager.cachedMainFile(for: c), c)
    await assertEqual(manager.cachedMainFile(for: d), d)

    await mainFiles.updateMainFiles(for: a, to: [a])
    await mainFiles.updateMainFiles(for: b, to: [c, d, a])

    await assertEqual(manager.cachedMainFile(for: a), c)
    await assertEqual(manager.cachedMainFile(for: b), bMain)
    await assertEqual(manager.cachedMainFile(for: c), c)
    await assertEqual(manager.cachedMainFile(for: d), d)

    await manager.mainFilesChanged()

    await assertEqual(manager.cachedMainFile(for: a), a)
    await assertEqual(manager.cachedMainFile(for: b), a)
    await assertEqual(manager.cachedMainFile(for: c), c)
    await assertEqual(manager.cachedMainFile(for: d), d)

    await manager.unregisterForChangeNotifications(for: a)
    await assertEqual(manager.cachedMainFile(for: a), nil)
    await assertEqual(manager.cachedMainFile(for: b), a)
    await assertEqual(manager.cachedMainFile(for: c), c)
    await assertEqual(manager.cachedMainFile(for: d), d)

    await manager.unregisterForChangeNotifications(for: b)
    await manager.mainFilesChanged()
    await manager.unregisterForChangeNotifications(for: c)
    await manager.unregisterForChangeNotifications(for: d)
    await assertEqual(manager.cachedMainFile(for: a), nil)
    await assertEqual(manager.cachedMainFile(for: b), nil)
    await assertEqual(manager.cachedMainFile(for: c), nil)
    await assertEqual(manager.cachedMainFile(for: d), nil)
  }

  func testSettingsMainFile() async throws {
    let a = try DocumentURI(string: "bsm:a.swift")
    let mainFiles = ManualMainFilesProvider([a: [a]])

    let (manager, buildServer) = try await createBuildServerManager(mainFilesProvider: mainFiles)

    let del = await BSMDelegate(manager)

    await buildServer.setBuildSettings(for: a, to: TextDocumentSourceKitOptionsResponse(compilerArguments: ["x"]))
    // Wait for the new build settings to settle before registering for change notifications
    await manager.waitForUpToDateBuildGraph()
    await manager.registerForChangeNotifications(for: a, language: .swift)
    assertEqual(
      await manager.buildSettingsInferredFromMainFile(for: a, language: .swift, fallbackAfterTimeout: false)?
        .compilerArguments.first,
      "x"
    )

    let changed = expectation(description: "changed settings")
    await del.setExpected([
      (a, .swift, fallbackBuildSettings(for: a, language: .swift, options: .init()), changed)
    ])
    await buildServer.setBuildSettings(for: a, to: nil)
    try await fulfillmentOfOrThrow(changed)
  }

  func testSettingsMainFileInitialNil() async throws {
    let a = try DocumentURI(string: "bsm:a.swift")
    let mainFiles = ManualMainFilesProvider([a: [a]])

    let (manager, buildServer) = try await createBuildServerManager(mainFilesProvider: mainFiles)

    let del = await BSMDelegate(manager)
    await manager.registerForChangeNotifications(for: a, language: .swift)

    let changed = expectation(description: "changed settings")
    await del.setExpected([(a, .swift, FileBuildSettings(compilerArguments: ["x"], language: .swift), changed)])
    await buildServer.setBuildSettings(for: a, to: TextDocumentSourceKitOptionsResponse(compilerArguments: ["x"]))
    try await fulfillmentOfOrThrow(changed)
  }

  func testSettingsMainFileWithFallback() async throws {
    let a = try DocumentURI(string: "bsm:a.swift")
    let mainFiles = ManualMainFilesProvider([a: [a]])

    let (manager, buildServer) = try await createBuildServerManager(mainFilesProvider: mainFiles)

    let del = await BSMDelegate(manager)
    let fallbackSettings = fallbackBuildSettings(for: a, language: .swift, options: .init())
    await manager.registerForChangeNotifications(for: a, language: .swift)
    assertEqual(
      await manager.buildSettingsInferredFromMainFile(for: a, language: .swift, fallbackAfterTimeout: false),
      fallbackSettings
    )

    let changed = expectation(description: "changed settings")
    await del.setExpected([
      (a, .swift, FileBuildSettings(compilerArguments: ["non-fallback", "args"], language: .swift), changed)
    ])
    await buildServer.setBuildSettings(
      for: a,
      to: TextDocumentSourceKitOptionsResponse(compilerArguments: ["non-fallback", "args"])
    )
    try await fulfillmentOfOrThrow(changed)

    let revert = expectation(description: "revert to fallback settings")
    await del.setExpected([(a, .swift, fallbackSettings, revert)])
    await buildServer.setBuildSettings(for: a, to: nil)
    try await fulfillmentOfOrThrow(revert)
  }

  func testSettingsHeaderChangeMainFile() async throws {
    let h = try DocumentURI(string: "bsm:header.h")
    let cpp1 = try DocumentURI(string: "bsm:main.cpp")
    let cpp2 = try DocumentURI(string: "bsm:other.cpp")
    let mainFiles = ManualMainFilesProvider(
      [
        h: [cpp1],
        cpp1: [cpp1],
        cpp2: [cpp2],
      ]
    )

    let (manager, buildServer) = try await createBuildServerManager(mainFilesProvider: mainFiles)

    let del = await BSMDelegate(manager)

    await buildServer.setBuildSettings(
      for: cpp1,
      to: TextDocumentSourceKitOptionsResponse(compilerArguments: ["C++ 1"])
    )
    await buildServer.setBuildSettings(
      for: cpp2,
      to: TextDocumentSourceKitOptionsResponse(compilerArguments: ["C++ 2"])
    )

    // Wait for the new build settings to settle before registering for change notifications
    await manager.waitForUpToDateBuildGraph()
    await manager.registerForChangeNotifications(for: h, language: .c)
    assertEqual(
      await manager.buildSettingsInferredFromMainFile(for: h, language: .c, fallbackAfterTimeout: false)?
        .compilerArguments.first,
      "C++ 1"
    )

    await mainFiles.updateMainFiles(for: h, to: [cpp2])

    let changed = expectation(description: "changed settings to cpp2")
    await del.setExpected([(h, .c, FileBuildSettings(compilerArguments: ["C++ 2"], language: .c), changed)])
    await manager.mainFilesChanged()
    try await fulfillmentOfOrThrow(changed)

    let changed2 = expectation(description: "still cpp2, no update")
    changed2.isInverted = true
    await del.setExpected([(h, .c, nil, changed2)])
    await manager.mainFilesChanged()
    try await fulfillmentOfOrThrow(changed2, timeout: 1)

    await mainFiles.updateMainFiles(for: h, to: [cpp1, cpp2])

    let changed3 = expectation(description: "added lexicographically earlier main file")
    await del.setExpected([(h, .c, FileBuildSettings(compilerArguments: ["C++ 1"], language: .c), changed3)])
    await manager.mainFilesChanged()
    try await fulfillmentOfOrThrow(changed3, timeout: 1)

    await mainFiles.updateMainFiles(for: h, to: [])

    let changed4 = expectation(description: "changed settings to []")
    await del.setExpected([
      (h, .c, fallbackBuildSettings(for: h, language: .cpp, options: .init()), changed4)
    ])
    await manager.mainFilesChanged()
    try await fulfillmentOfOrThrow(changed4)
  }

  func testSettingsOneMainTwoHeader() async throws {
    let h1 = try DocumentURI(string: "bsm:header1.h")
    let h2 = try DocumentURI(string: "bsm:header2.h")
    let cpp = try DocumentURI(string: "bsm:main.cpp")
    let mainFiles = ManualMainFilesProvider(
      [
        h1: [cpp],
        h2: [cpp],
      ]
    )

    let (manager, buildServer) = try await createBuildServerManager(mainFilesProvider: mainFiles)

    let del = await BSMDelegate(manager)

    let cppArg = "C++ Main File"
    await buildServer.setBuildSettings(
      for: cpp,
      to: TextDocumentSourceKitOptionsResponse(compilerArguments: [cppArg, cpp.pseudoPath])
    )

    // Wait for the new build settings to settle before registering for change notifications
    await manager.waitForUpToDateBuildGraph()

    await manager.registerForChangeNotifications(for: h1, language: .c)
    await manager.registerForChangeNotifications(for: h2, language: .c)

    assertEqual(
      await manager.buildSettingsInferredFromMainFile(for: h1, language: .c, fallbackAfterTimeout: false)?
        .compilerArguments.prefix(3),
      ["-xc++", cppArg, h1.pseudoPath]
    )
    assertEqual(
      await manager.buildSettingsInferredFromMainFile(for: h2, language: .c, fallbackAfterTimeout: false)?
        .compilerArguments.prefix(3),
      ["-xc++", cppArg, h2.pseudoPath]
    )

    let newCppArg = "New C++ Main File"
    let changed1 = expectation(description: "initial settings h1 via cpp")
    let changed2 = expectation(description: "initial settings h2 via cpp")
    let newArgsH1 = FileBuildSettings(compilerArguments: ["-xc++", newCppArg, h1.pseudoPath], language: .c)
    let newArgsH2 = FileBuildSettings(compilerArguments: ["-xc++", newCppArg, h2.pseudoPath], language: .c)
    await del.setExpected([
      (h1, .c, newArgsH1, changed1),
      (h2, .c, newArgsH2, changed2),
    ])
    await buildServer.setBuildSettings(
      for: cpp,
      to: TextDocumentSourceKitOptionsResponse(compilerArguments: [newCppArg, cpp.pseudoPath])
    )
    try await fulfillmentOfOrThrow(changed1, changed2)
  }
}

// MARK: Helper Classes for Testing

/// A simple `MainFilesProvider` that wraps a dictionary, for testing.
private final actor ManualMainFilesProvider: MainFilesProvider {
  private var mainFiles: [DocumentURI: Set<DocumentURI>]

  init(_ mainFiles: [DocumentURI: Set<DocumentURI>]) {
    self.mainFiles = mainFiles
  }

  func updateMainFiles(for file: DocumentURI, to mainFiles: Set<DocumentURI>) async {
    self.mainFiles[file] = mainFiles
  }

  func mainFiles(containing file: DocumentURI, crossLanguage: Bool) -> Set<DocumentURI> {
    if let result = mainFiles[file] {
      return result
    }
    return Set()
  }
}

/// A `BuildServerMangerDelegate` setup for testing.
private actor BSMDelegate: BuildServerManagerDelegate {
  func watchFiles(_ fileWatchers: [LanguageServerProtocol.FileSystemWatcher]) async {}

  fileprivate typealias ExpectedBuildSettingChangedCall = (
    uri: DocumentURI, language: Language, settings: FileBuildSettings?, expectation: XCTestExpectation,
    file: StaticString, line: UInt
  )
  fileprivate typealias ExpectedDependenciesUpdatedCall = (
    uri: DocumentURI, expectation: XCTestExpectation, file: StaticString, line: UInt
  )

  unowned let manager: BuildServerManager
  var expected: [ExpectedBuildSettingChangedCall] = []

  /// - Note: Needed to set `expected` outside of the actor's isolation context.
  func setExpected(
    _ expected: [(uri: DocumentURI, language: Language, settings: FileBuildSettings?, expectation: XCTestExpectation)],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    self.expected = expected.map { ($0.uri, $0.language, $0.settings, $0.expectation, file, line) }
  }

  init(_ manager: BuildServerManager) async {
    self.manager = manager
    await manager.setDelegate(self)
  }

  func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) async {
    for uri in changedFiles {
      guard let expectedIndex = expected.firstIndex(where: { $0.uri == uri }) else {
        XCTFail("unexpected settings change for \(uri)")
        continue
      }
      let expected = expected[expectedIndex]
      self.expected.remove(at: expectedIndex)

      XCTAssertEqual(uri, expected.uri, file: expected.file, line: expected.line)
      let settings = await manager.buildSettingsInferredFromMainFile(
        for: uri,
        language: expected.language,
        fallbackAfterTimeout: false
      )

      if let expectedSettings = expected.settings {
        let actualArgs = settings?.compilerArguments.prefix(expectedSettings.compilerArguments.count)
        XCTAssertEqual(
          actualArgs,
          ArraySlice(expectedSettings.compilerArguments),
          file: expected.file,
          line: expected.line
        )
        XCTAssertEqual(
          settings?.workingDirectory,
          expectedSettings.workingDirectory,
          file: expected.file,
          line: expected.line
        )
        XCTAssertEqual(settings?.isFallback, expectedSettings.isFallback, file: expected.file, line: expected.line)
      } else {
        XCTAssertNil(settings, file: expected.file, line: expected.line)
      }

      expected.expectation.fulfill()
    }
  }

  func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) {}

  func buildTargetsChanged(_ changedTargets: Set<BuildTargetIdentifier>?) async {}

  var clientSupportsWorkDoneProgress: Bool { false }

  nonisolated func sendNotificationToClient(_ notification: some NotificationType) {}

  func sendRequestToClient<R: RequestType>(_ request: R) async throws -> R.Response {
    throw ResponseError.methodNotFound(R.method)
  }

  func waitUntilInitialized() async {}
}
