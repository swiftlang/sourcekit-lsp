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
    XCTAssertTrue(fileContents.hasPrefix("import "))
  }
  
  func testOpenInterface() throws {
    guard let ws = try staticSourceKitSwiftPMWorkspace(name: "SwiftPMPackage") else { return }
    try ws.buildAndIndex()
    let importedModule = ws.testLoc("lib:import")
    try ws.openDocument(importedModule.url, language: .swift)
    let openInterface = OpenInterfaceRequest(textDocument: importedModule.docIdentifier, name: "lib")
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
