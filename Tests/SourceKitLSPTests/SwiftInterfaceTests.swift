//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import LanguageServerProtocol
import LSPTestSupport
import LSPLogging
import SKSupport
import SKTestSupport
import SourceKitLSP
import XCTest

final class SwiftInterfaceTests: XCTestCase {

  /// Connection and lifetime management for the service.
  var connection: TestSourceKitServer! = nil

  /// The primary interface to make requests to the SourceKitServer.
  var sk: TestClient! = nil

  var documentManager: DocumentManager! {
    connection.server!._documentManager
  }

  override func setUp() {
    connection = TestSourceKitServer()
    sk = connection.client
    _ = try! sk.sendSync(InitializeRequest(
      processId: nil,
      rootPath: nil,
      rootURI: nil,
      initializationOptions: nil,
      capabilities: ClientCapabilities(workspace: nil,
                                       textDocument: TextDocumentClientCapabilities(
                                        codeAction: .init(
                                          codeActionLiteralSupport: .init(
                                            codeActionKind: .init(valueSet: [.quickFix])
                                          )),
                                        publishDiagnostics: .init(codeDescriptionSupport: true)
                                       )),
      trace: .off,
      workspaceFolders: nil))
  }
  
  override func tearDown() {
    sk = nil
    connection = nil
  }
  
  func testSystemModuleInterface() throws {
    // This test is failing non-deterministically in CI becaue the file contents
    // of the generated interface just contain a newline.
    // I cannot reproduce the failure locally. Add some logging to determine
    // whether the issue is sourcekitd not returning an empty generated
    // interface or something around how the file is handled.
    // Remove this lowering of the log level once we have determined what the
    // issue is (rdar://104871745).
    let previousLogLevel = Logger.shared.currentLevel
    defer { Logger.shared.setLogLevel(previousLogLevel.description) }
    Logger.shared.setLogLevel("debug")

    let url = URL(fileURLWithPath: "/\(UUID())/a.swift")
    let uri = DocumentURI(url)

    sk.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
      uri: uri,
      language: .swift,
      version: 1,
      text: """
      import Foundation
      """)))
    
    let _resp = try sk.sendSync(DefinitionRequest(
      textDocument: TextDocumentIdentifier(url),
      position: Position(line: 0, utf16index: 10)))
    let resp = try XCTUnwrap(_resp)
    guard case .locations(let locations) = resp else {
      XCTFail("Unexpected response: \(resp)")
      return
    }
    XCTAssertEqual(locations.count, 1)
    let location = try XCTUnwrap(locations.first)
    XCTAssertTrue(location.uri.pseudoPath.hasSuffix("/Foundation.swiftinterface"))
    let fileContents = try XCTUnwrap(location.uri.fileURL.flatMap({ try String(contentsOf: $0, encoding: .utf8) }))
    // Sanity-check that the generated Swift Interface contains Swift code
    XCTAssert(fileContents.hasPrefix("import "), "Expected that the foundation swift interface starts with 'import ' but got '\(fileContents.prefix(100))'")
  }
  
  func testOpenInterface() throws {
    guard let ws = try staticSourceKitSwiftPMWorkspace(name: "SwiftPMPackage") else { return }
    try ws.buildAndIndex()
    let importedModule = ws.testLoc("lib:import")
    try ws.openDocument(importedModule.url, language: .swift)
    let openInterface = OpenInterfaceRequest(textDocument: importedModule.docIdentifier, name: "lib", symbolUSR: nil)
    let interfaceDetails = try XCTUnwrap(ws.sk.sendSync(openInterface))
    XCTAssertTrue(interfaceDetails.uri.pseudoPath.hasSuffix("/lib.swiftinterface"))
    let fileContents = try XCTUnwrap(interfaceDetails.uri.fileURL.flatMap({ try String(contentsOf: $0, encoding: .utf8) }))
    XCTAssertTrue(fileContents.contains("""
          public struct Lib {

              public func foo()

              public init()
          }
          """))
  }
  
  func testDefinitionInSystemModuleInterface() throws {
    guard let ws = try staticSourceKitSwiftPMWorkspace(name: "SwiftPMPackage") else { return }
    try ws.buildAndIndexWithSystemSymbols()
    let stringRef = ws.testLoc("Lib.a.string")
    try ws.openDocument(stringRef.url, language: .swift)
    let definition = try ws.sk.sendSync(DefinitionRequest(
      textDocument: stringRef.docIdentifier,
      position: stringRef.position))
    guard case .locations(let jump) = definition else {
      XCTFail("Response is not locations")
      return
    }
    let location = try XCTUnwrap(jump.first)
    XCTAssertTrue(location.uri.pseudoPath.hasSuffix("/Swift.String.swiftinterface"))
    // load contents of swiftinterface
    let contents = try XCTUnwrap(location.uri.fileURL.flatMap({ try String(contentsOf: $0, encoding: .utf8) }))
    let lineTable = LineTable(contents)
    let line = lineTable[location.range.lowerBound.line]
    XCTAssert(line.hasPrefix("@frozen public struct String"))
  }
  
  func testSwiftInterfaceAcrossModules() throws {
    guard let ws = try staticSourceKitSwiftPMWorkspace(name: "SwiftPMPackage") else { return }
    try ws.buildAndIndex()
    let importedModule = ws.testLoc("lib:import")
    try ws.openDocument(importedModule.url, language: .swift)
    let _resp = try withExtendedLifetime(ws) {
      try ws.sk.sendSync(DefinitionRequest(
        textDocument: importedModule.docIdentifier,
        position: importedModule.position))
    }
    let resp = try XCTUnwrap(_resp)
    guard case .locations(let locations) = resp else {
      XCTFail("Unexpected response: \(resp)")
      return
    }
    XCTAssertEqual(locations.count, 1)
    let location = try XCTUnwrap(locations.first)
    XCTAssertTrue(location.uri.pseudoPath.hasSuffix("/lib.swiftinterface"))
    let fileContents = try XCTUnwrap(location.uri.fileURL.flatMap({ try String(contentsOf: $0, encoding: .utf8) }))
    XCTAssertTrue(fileContents.contains("""
      public struct Lib {
      
          public func foo()
      
          public init()
      }
      """))
  }
}
