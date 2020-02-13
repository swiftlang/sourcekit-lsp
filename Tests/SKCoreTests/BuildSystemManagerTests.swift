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
    mainFiles.mainFiles = [
      a: Set([c]),
      b: Set([c, d]),
      c: Set([c]),
      d: Set([d]),
    ]

    let bsm = BuildSystemManager(
      buildSystem: FallbackBuildSystem(),
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
    mainFiles.mainFiles = [a: Set([a])]
    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(buildSystem: bs, mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[a] = FileBuildSettings(compilerArguments: ["x"], language: .swift)
    let initial = expectation(description: "initial settings")
    del.expected = [(a, bs.map[a]!, initial, #file, #line)]
    bsm.registerForChangeNotifications(for: a, language: .swift)
    wait(for: [initial], timeout: 10, enforceOrder: true)

    bs.map[a] = nil
    let changed = expectation(description: "changed settings")
    del.expected = [(a, nil, changed, #file, #line)]
    bsm.fileBuildSettingsChanged(Set([a]))
    wait(for: [changed], timeout: 10, enforceOrder: true)
  }

  func testSettingsMainFileInitialNil() {
    let a = DocumentURI(string: "bsm:a.swift")
    let mainFiles = ManualMainFilesProvider()
    mainFiles.mainFiles = [a: Set([a])]
    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(buildSystem: bs, mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)
    let initial = expectation(description: "initial settings")
    del.expected = [(a, nil, initial, #file, #line)]
    bsm.registerForChangeNotifications(for: a, language: .swift)
    wait(for: [initial], timeout: 10, enforceOrder: true)

    bs.map[a] = FileBuildSettings(compilerArguments: ["x"], language: .swift)
    let changed = expectation(description: "changed settings")
    del.expected = [(a, bs.map[a]!, changed, #file, #line)]
    bsm.fileBuildSettingsChanged(Set([a]))
    wait(for: [changed], timeout: 10, enforceOrder: true)
  }

  func testSettingsMainFileInitialIntersect() {
    let a = DocumentURI(string: "bsm:a.swift")
    let b = DocumentURI(string: "bsm:b.swift")
    let mainFiles = ManualMainFilesProvider()
    mainFiles.mainFiles = [a: Set([a]), b: Set([b])]
    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(buildSystem: bs, mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[a] = FileBuildSettings(compilerArguments: ["x"], language: .swift)
    bs.map[b] = FileBuildSettings(compilerArguments: ["y"], language: .swift)
    let initial = expectation(description: "initial settings")
    del.expected = [(a, bs.map[a]!, initial, #file, #line)]
    bsm.registerForChangeNotifications(for: a, language: .swift)
    wait(for: [initial], timeout: 10, enforceOrder: true)
    let initialB = expectation(description: "initial settings")
    del.expected = [(b, bs.map[b]!, initialB, #file, #line)]
    bsm.registerForChangeNotifications(for: b, language: .swift)
    wait(for: [initialB], timeout: 10, enforceOrder: true)

    bs.map[a] = FileBuildSettings(compilerArguments: ["xx"], language: .swift)
    bs.map[b] = FileBuildSettings(compilerArguments: ["yy"], language: .swift)
    let changed = expectation(description: "changed settings")
    del.expected = [(a, bs.map[a]!, changed, #file, #line)]
    bsm.fileBuildSettingsChanged(Set([a]))
    wait(for: [changed], timeout: 10, enforceOrder: true)

    bs.map[a] = FileBuildSettings(compilerArguments: ["xxx"], language: .swift)
    bs.map[b] = FileBuildSettings(compilerArguments: ["yyy"], language: .swift)
    let changedBothA = expectation(description: "changed setting a")
    let changedBothB = expectation(description: "changed setting b")
    del.expected = [
      (a, bs.map[a]!, changedBothA, #file, #line),
      (b, bs.map[b]!, changedBothB, #file, #line),
    ]
    bsm.fileBuildSettingsChanged(Set([])) // empty => all
    wait(for: [changedBothA, changedBothB], timeout: 10, enforceOrder: false)
  }

  func testSettingsMainFileUnchanged() {
    let a = DocumentURI(string: "bsm:a.swift")
    let b = DocumentURI(string: "bsm:b.swift")
    let mainFiles = ManualMainFilesProvider()
    mainFiles.mainFiles = [a: Set([a]), b: Set([b])]
    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(buildSystem: bs, mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[a] = FileBuildSettings(compilerArguments: ["a"], language: .swift)
    bs.map[b] = FileBuildSettings(compilerArguments: ["b"], language: .swift)

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
    bsm.fileBuildSettingsChanged(Set([b]))
    wait(for: [changed], timeout: 10, enforceOrder: true)
  }

  func testSettingsHeaderChangeMainFile() {
    let h = DocumentURI(string: "bsm:header.h")
    let cpp1 = DocumentURI(string: "bsm:main.cpp")
    let cpp2 = DocumentURI(string: "bsm:other.cpp")
    let mainFiles = ManualMainFilesProvider()
    mainFiles.mainFiles = [
      h: Set([cpp1]),
      cpp1: Set([cpp1]),
      cpp2: Set([cpp2]),
    ]

    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(buildSystem: bs, mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[cpp1] = FileBuildSettings(compilerArguments: ["C++ 1"], language: .cpp)
    bs.map[cpp2] = FileBuildSettings(compilerArguments: ["C++ 2"], language: .cpp)

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
    mainFiles.mainFiles = [
      h1: Set([cpp]),
      h2: Set([cpp]),
    ]

    let bs = ManualBuildSystem()
    let bsm = BuildSystemManager(buildSystem: bs, mainFilesProvider: mainFiles)
    let del = BSMDelegate(bsm)

    bs.map[cpp] = FileBuildSettings(compilerArguments: ["C++ Main File"], language: .cpp)

    let initial1 = expectation(description: "initial settings h1 via cpp")
    let initial2 = expectation(description: "initial settings h2 via cpp")
    del.expected = [
      (h1, bs.map[cpp]!, initial1, #file, #line),
      (h2, bs.map[cpp]!, initial2, #file, #line),
    ]

    bsm.registerForChangeNotifications(for: h1, language: .c)
    bsm.registerForChangeNotifications(for: h2, language: .c)

    wait(for: [initial1, initial2], timeout: 10, enforceOrder: true)

    bs.map[cpp] = FileBuildSettings(compilerArguments: ["New C++ Main File"], language: .cpp)
    let changed1 = expectation(description: "initial settings h1 via cpp")
    let changed2 = expectation(description: "initial settings h2 via cpp")
    del.expected = [
      (h1, bs.map[cpp]!, changed1, #file, #line),
      (h2, bs.map[cpp]!, changed2, #file, #line),
    ]
    bsm.fileBuildSettingsChanged(Set([cpp]))

    wait(for: [changed1, changed2], timeout: 10, enforceOrder: false)
  }
}

// MARK: Helper Classes for Testing

/// A simple `MainFilesProvider` that wraps a dictionary, for testing.
private final class ManualMainFilesProvider: MainFilesProvider {
  var mainFiles: [DocumentURI: Set<DocumentURI>] = [:]

  func mainFilesContainingFile(_ file: DocumentURI) -> Set<DocumentURI> {
    if let result = mainFiles[file] {
      return result
    }
    return Set()
  }
}

/// A simple `BuildSystem` that wraps a dictionary, for testing.
final class ManualBuildSystem: BuildSystem {
  var map: [DocumentURI: FileBuildSettings] = [:]

  var delegate: BuildSystemDelegate? = nil

  func settings(for uri: DocumentURI, _ language: Language) -> FileBuildSettings? {
    return map[uri]
  }

  func registerForChangeNotifications(for: DocumentURI, language: Language) {
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

  init(_ bsm: BuildSystemManager) {
    self.bsm = bsm
    bsm.delegate = self
  }

  func fileBuildSettingsChanged(_ changedFiles: Set<DocumentURI>) {
    queue.sync {
      for uri in changedFiles {
        guard let expected = expected.first(where: { $0.uri == uri }) else {
          XCTFail("unexpected settings change for \(uri)")
          continue
        }

        XCTAssertEqual(uri, expected.uri, file: expected.file, line: expected.line)
        let settings = bsm.settings(for: uri, .swift)
        XCTAssertEqual(settings, expected.settings, file: expected.file, line: expected.line)
        expected.expectation.fulfill()
      }
    }
  }

  func buildTargetsChanged(_ changes: [BuildTargetEvent]) {}
  func filesDependenciesUpdated(_ changedFiles: Set<DocumentURI>) {}
}
