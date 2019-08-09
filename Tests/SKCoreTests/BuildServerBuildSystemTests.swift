import XCTest
import SKCore
import Basic
import LanguageServerProtocol

final class BuildServerBuildSystemTests: XCTestCase, BuildSystemDelegate {

  var didGetDelegateCall = false

  func testIndexPaths() {
    let root = AbsolutePath(
      inputsDirectory().appendingPathComponent(testDirectoryName, isDirectory: true).path)
    let buildFolder = AbsolutePath(NSTemporaryDirectory())

    let buildSystem = try? BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    XCTAssertNotNil(buildSystem)
    XCTAssertEqual(buildSystem?.indexStorePath, AbsolutePath("/tmp/index/store"))
    XCTAssertEqual(buildSystem?.indexDatabasePath, buildFolder.appending(components: "index", "db"))
  }

  func testSettings() {
    let root = AbsolutePath(
      inputsDirectory().appendingPathComponent(testDirectoryName, isDirectory: true).path)
    let buildSystem = try! BuildServerBuildSystem(projectRoot: root, buildFolder: nil)
    let settings = buildSystem.settings(for: URL(fileURLWithPath: "some_file.swift"), Language.swift)!

    XCTAssertEqual(settings.compilerArguments, ["a", "b"])
    XCTAssertNil(settings.workingDirectory)
  }

  func testDelegate() {
    let root = AbsolutePath(
      inputsDirectory().appendingPathComponent(testDirectoryName, isDirectory: true).path)
    let buildSystem = try! BuildServerBuildSystem(projectRoot: root, buildFolder: nil)
    buildSystem.delegate = self

    // request settings to trigger refresh notification
    _ = buildSystem.settings(for: URL(fileURLWithPath: "some_file.swift"), Language.swift)

    XCTAssertTrue(didGetDelegateCall)
  }

  // MARK: - BuildSystemDelegate

  func refreshDocuments(_ urls: [URL]) {
    didGetDelegateCall = true
    XCTAssertEqual(urls, [URL(string: "a"), URL(string: "b")])
  }
}
