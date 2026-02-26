//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import XCTest

final class UnderscoredAttributeFilteringTests: SourceKitLSPTestCase {
  
  func testUnderscoredAttributesNotShownInHover() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      @_staticExclusiveOnly
      public struct My1️⃣Struct {
          var x: Int
      }
      
      @_rawLayout(like: T)
      public struct MyRaw2️⃣Layout<T> {
          var data: T
      }
      """,
      uri: uri
    )
    
    let hoverResponse1 = try await testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    
    guard case .markupContent(let content1) = hoverResponse1?.contents else {
      XCTFail("Expected markup content in hover response")
      return
    }
    
    XCTAssertTrue(content1.value.contains("struct MyStruct"), "Hover should contain the struct name")
    XCTAssertFalse(content1.value.contains("@_staticExclusiveOnly"), "Hover should NOT contain @_staticExclusiveOnly")
    
    let hoverResponse2 = try await testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["2️⃣"])
    )
    
    guard case .markupContent(let content2) = hoverResponse2?.contents else {
      XCTFail("Expected markup content in hover response")
      return
    }
    
    XCTAssertTrue(content2.value.contains("struct MyRawLayout"), "Hover should contain the struct name")
    XCTAssertFalse(content2.value.contains("@_rawLayout"), "Hover should NOT contain @_rawLayout")
  }
  
  func testRegularAttributesStillShownInHover() async throws {
    let testClient = try await TestSourceKitLSPClient()
    let uri = DocumentURI(for: .swift)
    let positions = testClient.openDocument(
      """
      @available(*, deprecated)
      public struct My1️⃣Struct {
          var x: Int
      }
      """,
      uri: uri
    )
    
    let hoverResponse = try await testClient.send(
      HoverRequest(textDocument: TextDocumentIdentifier(uri), position: positions["1️⃣"])
    )
    
    guard case .markupContent(let content) = hoverResponse?.contents else {
      XCTFail("Expected markup content in hover response")
      return
    }
    
    XCTAssertTrue(content.value.contains("struct MyStruct"), "Hover should contain the struct name")
    XCTAssertFalse(content.value.contains("@_"), "Hover should NOT contain any underscored attributes")
  }
}
