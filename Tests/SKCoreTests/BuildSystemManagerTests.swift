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

import LanguageServerProtocol
import BuildServerProtocol
import LSPTestSupport
import SKCore
import TSCBasic
import XCTest

final class BuildSystemManagerTests: XCTestCase {

  func testMainFiles() {
    let a = DocumentURI(string: "bsm:a")
    let b = DocumentURI(string: "bsm:b")
    let c = DocumentURI(string: "bsm:c")
    let d = DocumentURI(string: "bsm:d")

    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [
      a: Set([c]),
      b: Set([c, d]),
      c: Set([c]),
      d: Set([d]),
    ]

    let bsm = BuildSystemManager(
      buildSystem: FallbackBuildSystem(),
      fallbackBuildSystem: nil,
      mainFilesProvider: mainFiles)

    XCTAssertEqual(bsm._cachedMainFile(for: a), nil)
    XCTAssertEqual(bsm._cachedMainFile(for: b), nil)
    XCTAssertEqual(bsm._cachedMainFile(for: c), nil)
    XCTAssertEqual(bsm._cachedMainFile(for: d), nil)

    bsm.registerForChangeNotifications(for: a, language: .c)
    bsm.registerForChangeNotifications(for: b, language: .c)
    bsm.registerForChangeNotifications(for: c, language: .c)
    bsm.registerForChangeNotifications(for: d, language: .c)
    XCTAssertEqual(bsm._cachedMainFile(for: a), c)
    let bMain = bsm._cachedMainFile(for: b)
    XCTAssert(Set([c, d]).contains(bMain))
    XCTAssertEqual(bsm._cachedMainFile(for: c), c)
    XCTAssertEqual(bsm._cachedMainFile(for: d), d)

    mainFiles.mainFiles = [
      a: Set([a]),
      b: Set([c, d, a]),
      c: Set([c]),
      d: Set([d]),
    ]

    XCTAssertEqual(bsm._cachedMainFile(for: a), c)
    XCTAssertEqual(bsm._cachedMainFile(for: b), bMain)
    XCTAssertEqual(bsm._cachedMainFile(for: c), c)
    XCTAssertEqual(bsm._cachedMainFile(for: d), d)

    bsm.mainFilesChanged()

    XCTAssertEqual(bsm._cachedMainFile(for: a), a)
    XCTAssertEqual(bsm._cachedMainFile(for: b), bMain) // never changes to a
    XCTAssertEqual(bsm._cachedMainFile(for: c), c)
    XCTAssertEqual(bsm._cachedMainFile(for: d), d)

    bsm.unregisterForChangeNotifications(for: a)
    XCTAssertEqual(bsm._cachedMainFile(for: a), nil)
    XCTAssertEqual(bsm._cachedMainFile(for: b), bMain) // never changes to a
    XCTAssertEqual(bsm._cachedMainFile(for: c), c)
    XCTAssertEqual(bsm._cachedMainFile(for: d), d)

    bsm.unregisterForChangeNotifications(for: b)
    bsm.mainFilesChanged()
    bsm.unregisterForChangeNotifications(for: c)
    bsm.unregisterForChangeNotifications(for: d)
    XCTAssertEqual(bsm._cachedMainFile(for: a), nil)
    XCTAssertEqual(bsm._cachedMainFile(for: b), nil)
    XCTAssertEqual(bsm._cachedMainFile(for: c), nil)
    XCTAssertEqual(bsm._cachedMainFile(for: d), nil)
  }

  func testSettingsMainFile() {
    let a = DocumentURI(string: "bsm:a.swift")
    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [a: Set([a])]
    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(
      buildSystem: bs,
      fallbackBuildSystem: nil,
      mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[a] = FileBuildSettings(compilerArguments: ["x"])
    let initial = expectation(description: "initial settings")
    del.expected = [(a, bs.map[a]!, initial, #file, #line)]
    bsm.registerForChangeNotifications(for: a, language: .swift)
    wait(for: [initial], timeout: 10, enforceOrder: true)

    bs.map[a] = nil
    let changed = expectation(description: "changed settings")
    del.expected = [(a, nil, changed, #file, #line)]
    bsm.fileBuildSettingsChanged([a: .removedOrUnavailable])
    wait(for: [changed], timeout: 10, enforceOrder: true)
  }

  func testSettingsMainFileInitialNil() {
    let a = DocumentURI(string: "bsm:a.swift")
    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [a: Set([a])]
    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(
      buildSystem: bs,
      fallbackBuildSystem: nil,
      mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)
    let initial = expectation(description: "initial settings")
    del.expected = [(a, nil, initial, #file, #line)]
    bsm.registerForChangeNotifications(for: a, language: .swift)
    wait(for: [initial], timeout: 10, enforceOrder: true)

    bs.map[a] = FileBuildSettings(compilerArguments: ["x"])
    let changed = expectation(description: "changed settings")
    del.expected = [(a, bs.map[a]!, changed, #file, #line)]
    bsm.fileBuildSettingsChanged([a: .modified(bs.map[a]!)])
    wait(for: [changed], timeout: 10, enforceOrder: true)
  }

  func testSettingsMainFileWithFallback() {
    let a = DocumentURI(string: "bsm:a.swift")
    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [a: Set([a])]
    let bs = ManualBuildSystem()
    let fallback = FallbackBuildSystem()
    let bsm = BuildSystemManager(
      buildSystem: bs,
      fallbackBuildSystem: fallback,
      mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)
    let fallbackSettings = fallback.settings(for: a, .swift)
    let initial = expectation(description: "initial fallback settings")
    del.expected = [(a, fallbackSettings, initial, #file, #line)]
    bsm.registerForChangeNotifications(for: a, language: .swift)
    wait(for: [initial], timeout: 10, enforceOrder: true)

    bs.map[a] = FileBuildSettings(compilerArguments: ["non-fallback", "args"])
    let changed = expectation(description: "changed settings")
    del.expected = [(a, bs.map[a]!, changed, #file, #line)]
    bsm.fileBuildSettingsChanged([a: .modified(bs.map[a]!)])
    wait(for: [changed], timeout: 10, enforceOrder: true)

    bs.map[a] = nil
    let revert = expectation(description: "revert to fallback settings")
    del.expected = [(a, fallbackSettings, revert, #file, #line)]
    bsm.fileBuildSettingsChanged([a: .removedOrUnavailable])
    wait(for: [revert], timeout: 10, enforceOrder: true)
  }

  func testSettingsMainFileInitialIntersect() {
    let a = DocumentURI(string: "bsm:a.swift")
    let b = DocumentURI(string: "bsm:b.swift")
    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [a: Set([a]), b: Set([b])]
    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(
      buildSystem: bs,
      fallbackBuildSystem: nil,
      mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[a] = FileBuildSettings(compilerArguments: ["x"])
    bs.map[b] = FileBuildSettings(compilerArguments: ["y"])
    let initial = expectation(description: "initial settings")
    del.expected = [(a, bs.map[a]!, initial, #file, #line)]
    bsm.registerForChangeNotifications(for: a, language: .swift)
    wait(for: [initial], timeout: 10, enforceOrder: true)
    let initialB = expectation(description: "initial settings")
    del.expected = [(b, bs.map[b]!, initialB, #file, #line)]
    bsm.registerForChangeNotifications(for: b, language: .swift)
    wait(for: [initialB], timeout: 10, enforceOrder: true)

    bs.map[a] = FileBuildSettings(compilerArguments: ["xx"])
    bs.map[b] = FileBuildSettings(compilerArguments: ["yy"])
    let changed = expectation(description: "changed settings")
    del.expected = [(a, bs.map[a]!, changed, #file, #line)]
    bsm.fileBuildSettingsChanged([a: .modified(bs.map[a]!)])
    wait(for: [changed], timeout: 10, enforceOrder: true)

    // Test multiple changes.
    bs.map[a] = FileBuildSettings(compilerArguments: ["xxx"])
    bs.map[b] = FileBuildSettings(compilerArguments: ["yyy"])
    let changedBothA = expectation(description: "changed setting a")
    let changedBothB = expectation(description: "changed setting b")
    del.expected = [
      (a, bs.map[a]!, changedBothA, #file, #line),
      (b, bs.map[b]!, changedBothB, #file, #line),
    ]
    bsm.fileBuildSettingsChanged([
      a:. modified(bs.map[a]!),
      b: .modified(bs.map[b]!)
    ])
    wait(for: [changedBothA, changedBothB], timeout: 10, enforceOrder: false)
  }

  func testSettingsMainFileUnchanged() {
    let a = DocumentURI(string: "bsm:a.swift")
    let b = DocumentURI(string: "bsm:b.swift")
    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [a: Set([a]), b: Set([b])]
    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(
      buildSystem: bs,
      fallbackBuildSystem: nil,
      mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[a] = FileBuildSettings(compilerArguments: ["a"])
    bs.map[b] = FileBuildSettings(compilerArguments: ["b"])

    let initialA = expectation(description: "initial settings a")
    del.expected = [(a, bs.map[a]!, initialA, #file, #line)]
    bsm.registerForChangeNotifications(for: a, language: .swift)
    wait(for: [initialA], timeout: 10, enforceOrder: true)

    let initialB = expectation(description: "initial settings b")
    del.expected = [(b, bs.map[b]!, initialB, #file, #line)]
    bsm.registerForChangeNotifications(for: b, language: .swift)
    wait(for: [initialB], timeout: 10, enforceOrder: true)

    bs.map[a] = nil
    bs.map[b] = nil
    let changed = expectation(description: "changed settings")
    del.expected = [(b, nil, changed, #file, #line)]
    bsm.fileBuildSettingsChanged([
      b: .removedOrUnavailable
    ])
    wait(for: [changed], timeout: 10, enforceOrder: true)
  }

  func testSettingsHeaderChangeMainFile() {
    let h = DocumentURI(string: "bsm:header.h")
    let cpp1 = DocumentURI(string: "bsm:main.cpp")
    let cpp2 = DocumentURI(string: "bsm:other.cpp")
    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [
      h: Set([cpp1]),
      cpp1: Set([cpp1]),
      cpp2: Set([cpp2]),
    ]

    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(
      buildSystem: bs,
      fallbackBuildSystem: nil,
      mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[cpp1] = FileBuildSettings(compilerArguments: ["C++ 1"])
    bs.map[cpp2] = FileBuildSettings(compilerArguments: ["C++ 2"])

    let initial = expectation(description: "initial settings via cpp1")
    del.expected = [(h, bs.map[cpp1]!, initial, #file, #line)]
    bsm.registerForChangeNotifications(for: h, language: .c)
    wait(for: [initial], timeout: 10, enforceOrder: true)

    mainFiles.mainFiles[h] = Set([cpp2])

    let changed = expectation(description: "changed settings to cpp2")
    del.expected = [(h, bs.map[cpp2]!, changed, #file, #line)]
    bsm.mainFilesChanged()
    wait(for: [changed], timeout: 10, enforceOrder: true)

    let changed2 = expectation(description: "still cpp2, no update")
    changed2.isInverted = true
    del.expected = [(h, nil, changed2, #file, #line)]
    bsm.mainFilesChanged()
    wait(for: [changed2], timeout: 1, enforceOrder: true)

    mainFiles.mainFiles[h] = Set([cpp1, cpp2])

    let changed3 = expectation(description: "added main file, no update")
    changed3.isInverted = true
    del.expected = [(h, nil, changed3, #file, #line)]
    bsm.mainFilesChanged()
    wait(for: [changed3], timeout: 1, enforceOrder: true)

    mainFiles.mainFiles[h] = Set([])

    let changed4 = expectation(description: "changed settings to []")
    del.expected = [(h, nil, changed4, #file, #line)]
    bsm.mainFilesChanged()
    wait(for: [changed4], timeout: 10, enforceOrder: true)
  }

  func testSettingsOneMainTwoHeader() {
    let h1 = DocumentURI(string: "bsm:header1.h")
    let h2 = DocumentURI(string: "bsm:header2.h")
    let cpp = DocumentURI(string: "bsm:main.cpp")
    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [
      h1: Set([cpp]),
      h2: Set([cpp]),
    ]

    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(
      buildSystem: bs,
      fallbackBuildSystem: nil,
      mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[cpp] = FileBuildSettings(compilerArguments: ["C++ Main File"])

    let initial1 = expectation(description: "initial settings h1 via cpp")
    let initial2 = expectation(description: "initial settings h2 via cpp")
    del.expected = [
      (h1, bs.map[cpp]!, initial1, #file, #line),
      (h2, bs.map[cpp]!, initial2, #file, #line),
    ]

    bsm.registerForChangeNotifications(for: h1, language: .c)
    bsm.registerForChangeNotifications(for: h2, language: .c)

    // Since the registration is async, it's possible that they get grouped together
    // since they are backed by the same underlying cpp file.
    wait(for: [initial1, initial2], timeout: 10, enforceOrder: false)

    bs.map[cpp] = FileBuildSettings(compilerArguments: ["New C++ Main File"])
    let changed1 = expectation(description: "initial settings h1 via cpp")
    let changed2 = expectation(description: "initial settings h2 via cpp")
    del.expected = [
      (h1, bs.map[cpp]!, changed1, #file, #line),
      (h2, bs.map[cpp]!, changed2, #file, #line),
    ]
    bsm.fileBuildSettingsChanged([cpp: .modified(bs.map[cpp]!)])

    wait(for: [changed1, changed2], timeout: 10, enforceOrder: false)
  }

  func testSettingsChangedAfterUnregister() {
    let a = DocumentURI(string: "bsm:a.swift")
    let b = DocumentURI(string: "bsm:b.swift")
    let c = DocumentURI(string: "bsm:c.swift")
    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [a: Set([a]), b: Set([b]), c: Set([c])]
    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(
      buildSystem: bs,
      fallbackBuildSystem: nil,
      mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[a] = FileBuildSettings(compilerArguments: ["a"])
    bs.map[b] = FileBuildSettings(compilerArguments: ["b"])
    bs.map[c] = FileBuildSettings(compilerArguments: ["c"])

    let initialA = expectation(description: "initial settings a")
    let initialB = expectation(description: "initial settings b")
    let initialC = expectation(description: "initial settings c")
    del.expected = [
      (a, bs.map[a]!, initialA, #file, #line),
      (b, bs.map[b]!, initialB, #file, #line),
      (c, bs.map[c]!, initialC, #file, #line),
    ]
    bsm.registerForChangeNotifications(for: a, language: .swift)
    bsm.registerForChangeNotifications(for: b, language: .swift)
    bsm.registerForChangeNotifications(for: c, language: .swift)
    wait(for: [initialA, initialB, initialC], timeout: 10, enforceOrder: false)

    bs.map[a] = FileBuildSettings(compilerArguments: ["new-a"])
    bs.map[b] = FileBuildSettings(compilerArguments: ["new-b"])
    bs.map[c] = FileBuildSettings(compilerArguments: ["new-c"])

    let changedB = expectation(description: "changed settings b")
    del.expected = [
      (b, bs.map[b]!, changedB, #file, #line),
    ]

    bsm.unregisterForChangeNotifications(for: a)
    bsm.unregisterForChangeNotifications(for: c)
    // At this point only b is registered, but that can race with notifications,
    // so ensure nothing bad happens and we still get the notification for b.
    bsm.fileBuildSettingsChanged([
      a: .modified(bs.map[a]!),
      b: .modified(bs.map[b]!),
      c: .modified(bs.map[c]!)
    ])

    wait(for: [changedB], timeout: 10, enforceOrder: false)
  }

  func testDependenciesUpdated() {
    let a = DocumentURI(string: "bsm:a.swift")
    let mainFiles = ManualMainFilesProvider()
    defer {
      // BuildSystemManager has a weak reference to mainFiles. Keep it alive.
      _fixLifetime(mainFiles)
    }
    mainFiles.mainFiles = [a: Set([a])]

    class DepUpdateDuringRegistrationBS: ManualBuildSystem {
        override func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
          delegate?.filesDependenciesUpdated([uri])
          super.registerForChangeNotifications(for: uri, language: language)
        }
    }

    let bs = DepUpdateDuringRegistrationBS()
    let bsm = BuildSystemManager(
      buildSystem: bs,
      fallbackBuildSystem: nil,
      mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[a] = FileBuildSettings(compilerArguments: ["x"])
    let initial = expectation(description: "initial settings")
    del.expected = [(a, bs.map[a]!, initial, #file, #line)]

    let depUpdate1 = expectation(description: "dependencies update during registration")
    del.expectedDependenciesUpdate = [(a, depUpdate1, #file, #line)]

    bsm.registerForChangeNotifications(for: a, language: .swift)
    wait(for: [initial, depUpdate1], timeout: 10, enforceOrder: false)

    let depUpdate2 = expectation(description: "dependencies update 2")
    del.expectedDependenciesUpdate = [(a, depUpdate2, #file, #line)]

    bsm.filesDependenciesUpdated([a])
    wait(for: [depUpdate2], timeout: 10, enforceOrder: false)
  }
}

// MARK: Helper Classes for Testing

/// A simple `MainFilesProvider` that wraps a dictionary, for testing.
private final class ManualMainFilesProvider: MainFilesProvider {
  let lock: DispatchQueue = DispatchQueue(label: "\(ManualMainFilesProvider.self)-lock")
  private var _mainFiles: [DocumentURI: Set<DocumentURI>] = [:]
  var mainFiles: [DocumentURI: Set<DocumentURI>] {
    get { lock.sync { _mainFiles } }
    set { lock.sync { _mainFiles = newValue } }
  }

  func mainFilesContainingFile(_ file: DocumentURI) -> Set<DocumentURI> {
    if let result = mainFiles[file] {
      return result
    }
    return Set()
  }
}

/// A simple `BuildSystem` that wraps a dictionary, for testing.
class ManualBuildSystem: BuildSystem {
  var map: [DocumentURI: FileBuildSettings] = [:]

  var delegate: BuildSystemDelegate? = nil

  func settings(for uri: DocumentURI, _ language: Language) -> FileBuildSettings? {
    return map[uri]
  }

  func registerForChangeNotifications(for uri: DocumentURI, language: Language) {
    let settings = self.settings(for: uri, language)
    self.delegate?.fileBuildSettingsChanged([uri: FileBuildSettingsChange(settings)])
  }

  func unregisterForChangeNotifications(for: DocumentURI) {
  }

  var indexStorePath: AbsolutePath? { nil }
  var indexDatabasePath: AbsolutePath? { nil }

  func buildTargets(reply: @escaping (LSPResult<[BuildTarget]>) -> Void) {
    fatalError()
  }

  func buildTargetSources(targets: [BuildTargetIdentifier],
    reply: @escaping (LSPResult<[SourcesItem]>) -> Void) {
    fatalError()
  }

  func buildTargetOutputPaths(targets: [BuildTargetIdentifier],
    reply: @escaping (LSPResult<[OutputsItem]>) -> Void) {
    fatalError()
  }
}

/// A `BuildSystemDelegate` setup for testing.
private final class BSMDelegate: BuildSystemDelegate {
  let queue: DispatchQueue = DispatchQueue(label: "\(BSMDelegate.self)")
  unowned let bsm: BuildSystemManager
  var expected: [(uri: DocumentURI, settings: FileBuildSettings?, expectation: XCTestExpectation, file: StaticString, line: UInt)] = []
  var expectedDependenciesUpdate: [(uri: DocumentURI, expectation: XCTestExpectation, file: StaticString, line: UInt)] = []

  init(_ bsm: BuildSystemManager) {
    self.bsm = bsm
    bsm.delegate = self
  }

  func fileBuildSettingsChanged(_ changes: [DocumentURI: FileBuildSettingsChange]) {
    queue.sync {
      for (uri, change) in changes {
        guard let expected = expected.first(where: { $0.uri == uri }) else {
          XCTFail("unexpected settings change for \(uri)")
          continue
        }

        XCTAssertEqual(uri, expected.uri, file: expected.file, line: expected.line)
        let settings = change.newSettings
        XCTAssertEqual(settings, expected.settings, file: expected.file, line: expected.line)
        expected.expectation.fulfill()
      }
    }
  }

  func buildTargetsChanged(_ changes: [BuildTargetEvent]) {}
  func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) {
    queue.sync {
      for uri in changedFiles {
        guard let expected = expectedDependenciesUpdate.first(where: { $0.uri == uri }) else {
          XCTFail("unexpected filesDependenciesUpdated for \(uri)")
          continue
        }

        XCTAssertEqual(uri, expected.uri, file: expected.file, line: expected.line)
        expected.expectation.fulfill()
      }
    }
  }
}
