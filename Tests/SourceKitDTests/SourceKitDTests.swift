//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SourceKitD
import SKCore
import TSCBasic
import TSCUtility
import XCTest

final class SourceKitDTests: XCTestCase {
  static var sourcekitdPath: AbsolutePath! = nil
  static var sdkpath: String? = nil

  override class func setUp() {
    sourcekitdPath = ToolchainRegistry.shared.default!.sourcekitd!
    if case .darwin? = Platform.currentPlatform,
       let str = try? Process.checkNonZeroExit(
        args: "/usr/bin/xcrun", "--show-sdk-path", "--sdk", "macosx")
    {
      sdkpath = str.spm_chomp()
    }
  }

  func testMultipleNotificationHandlers() {
    let sourcekitd = try! SourceKitDImpl.getOrCreate(dylibPath: SourceKitDTests.sourcekitdPath)
    let keys = sourcekitd.keys

    let expectation1 = expectation(description: "handler 1")
    let handler1 = ClosureNotificationHandler { response in
      XCTAssertEqual(response.value?[keys.notification], sourcekitd.values.notification_documentupdate)
      expectation1.fulfill()
    }
    sourcekitd.addNotificationHandler(handler1)

    let expectation2 = expectation(description: "handler 2")
    let handler2 = ClosureNotificationHandler { response in
      XCTAssertEqual(response.value?[keys.notification], sourcekitd.values.notification_documentupdate)
      expectation2.fulfill()
    }
    sourcekitd.addNotificationHandler(handler2)

    let req = SKDRequestDictionary(sourcekitd: sourcekitd)
    req[keys.request] = sourcekitd.requests.editor_open
    let path: String = #file
    req[keys.name] = path
    req[keys.sourcetext] = """
      func foo() {}
      """
    let args = SKDRequestArray(sourcekitd: sourcekitd)
    if let sdkpath = SourceKitDTests.sdkpath {
      args.append("-sdk")
      args.append(sdkpath)
    }
    args.append(path)
    req[keys.compilerargs] = args

    _ = try! sourcekitd.sendSync(req)

    waitForExpectations(timeout: 15)

    let close = SKDRequestDictionary(sourcekitd: sourcekitd)
    close[keys.request] = sourcekitd.requests.editor_close
    close[keys.name] = path
    _ = try! sourcekitd.sendSync(close)
  }
}

private class ClosureNotificationHandler: SKDNotificationHandler {
  let f: (SKDResponse) -> Void

  init(_ f: @escaping (SKDResponse) -> Void) {
    self.f = f
  }

  func notification(_ response: SKDResponse) {
    f(response)
  }
}
