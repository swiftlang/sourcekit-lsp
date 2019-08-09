import XCTest
import SKCore
import Basic
import LanguageServerProtocol

final class BuildServerBuildSystemTests: XCTestCase {

  func testInitParsesConfig() {
    let root = AbsolutePath(
      inputsDirectory().appendingPathComponent(testDirectoryName, isDirectory: true).path)
    let buildFolder = AbsolutePath(NSTemporaryDirectory())

    let buildSystem = try? BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    XCTAssertNotNil(buildSystem)
  }

  func testServerInitialize() {
    let root = AbsolutePath(
      inputsDirectory().appendingPathComponent(testDirectoryName, isDirectory: true).path)
    let buildFolder = AbsolutePath(NSTemporaryDirectory())

    let buildSystem = try? BuildServerBuildSystem(projectRoot: root, buildFolder: buildFolder)

    XCTAssertNotNil(buildSystem)
    XCTAssertTrue(buildSystem!.initialize())
  }

}
