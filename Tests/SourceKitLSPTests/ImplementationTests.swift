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

import ISDBTestSupport
import LanguageServerProtocol
import SKTestSupport
import TSCBasic
import XCTest

final class ImplementationTests: XCTestCase {
  // MARK: - Utilities

  private func testImplementation(
    _ markedText: String,
    expectedLocations expectedLocationMarkers: [String] = ["2️⃣"],
    testName: String = #function,
    line: UInt = #line
  ) async throws {
    let project = try await IndexedSingleSwiftFileTestProject(markedText, testName: testName)
    let response = try await project.testClient.send(
      ImplementationRequest(
        textDocument: TextDocumentIdentifier(project.fileURI),
        position: project.positions["1️⃣"]
      )
    )
    guard case .locations(let implementations) = response else {
      XCTFail("Response was not locations", line: line)
      return
    }
    let expectedLocations = expectedLocationMarkers.map {
      Location(uri: project.fileURI, range: Range(project.positions[$0]))
    }
    XCTAssertEqual(implementations, expectedLocations, line: line)
  }

  // MARK: - Tests

  func testProtocolInheritance() async throws {
    try await testImplementation(
      """
      protocol 1️⃣Protocol {}
      struct Struct: 2️⃣Protocol {}
      """
    )
  }

  func testProtocolStaticVar() async throws {
    try await testImplementation(
      """
      protocol Protocol {
        static var 1️⃣staticVar: Int { get }
      }
      struct Struct: Protocol {
        static var 2️⃣staticVar: Int { 123 }
      }
      """
    )
  }

  func testProtocolStaticFunc() async throws {
    try await testImplementation(
      """
      protocol Protocol {
        static func 1️⃣staticFunction()
      }
      struct Struct: Protocol {
        static func 2️⃣staticFunction() {}
      }
      """
    )
  }

  func testProtocolVar() async throws {
    try await testImplementation(
      """
      protocol Protocol {
        var 1️⃣variable: Int { get }
      }
      struct Struct: Protocol {
        var 2️⃣variable: Int { 123 }
      }
      """
    )
  }

  func testProtocolFunc() async throws {
    try await testImplementation(
      """
      protocol Protocol {
        func 1️⃣function()
      }
      struct Struct: Protocol {
        func 2️⃣function() {}
      }
      """
    )
  }

  func testClassInheritance() async throws {
    try await testImplementation(
      """
      class 1️⃣Class {}
      class Subclass: 2️⃣Class {}
      """
    )
  }

  func testClassClassVar() async throws {
    try await testImplementation(
      """
      class Class {
        class var 1️⃣classVar: Int { 123 }
      }
      class Subclass: Class {
        override class var 2️⃣classVar: Int { 123 }
      }
      """
    )
  }

  func testClassClassFunc() async throws {
    try await testImplementation(
      """
      class Class {
        class func 1️⃣classFunction() {}
      }
      class Subclass: Class {
        override class func 2️⃣classFunction() {}
      }
      """
    )
  }

  func testClassVar() async throws {
    try await testImplementation(
      """
      class Class {
        var 1️⃣variable: Int { 123 }
      }
      class Subclass: Class {
        override var 2️⃣variable: Int { 123 }
      }
      """
    )
  }

  func testClassFunc() async throws {
    try await testImplementation(
      """
      class Class {
        func 1️⃣function() {}
      }
      class Subclass: Class {
        override func 2️⃣function() {}
      }
      """
    )
  }

  func testClassHierarchy() async throws {
    try await testImplementation(
      """
      class 1️⃣MyClass {}
      class SubA: 2️⃣MyClass {}
      class SubASub: SubA {}
      class SubB: 3️⃣MyClass {}
      class SubC: 4️⃣MyClass {}
      """,
      expectedLocations: ["2️⃣", "3️⃣", "4️⃣"]
    )
  }

  func testSubclassHierarchy() async throws {
    try await testImplementation(
      """
      class MyClass {}
      class 1️⃣Subclass: MyClass {}
      class SubSubClassA: 2️⃣Subclass {}
      class SubSubClassB: 3️⃣Subclass {}

      """,
      expectedLocations: ["2️⃣", "3️⃣"]
    )
  }

  func testProtocolHierarchy() async throws {
    try await testImplementation(
      """
      protocol 1️⃣MyProtocol {}
      protocol OtherProtocol: 2️⃣MyProtocol {}

      class ClassA: 3️⃣MyProtocol {}
      class ClassB: OtherProtocol, 4️⃣MyProtocol {}
      """,
      expectedLocations: ["2️⃣", "3️⃣", "4️⃣"]
    )
  }

  func testProtocolConformanceInExtension() async throws {
    try await testImplementation(
      """
      protocol 1️⃣MyProtocol {}
      class MyClass {}
      extension MyClass: 2️⃣MyProtocol {}
      """
    )
  }

  func testStandaloneClass() async throws {
    try await testImplementation(
      """
      class 1️⃣MyClass {}
      """,
      expectedLocations: []
    )
  }

  func testStandaloneClassFunc() async throws {
    try await testImplementation(
      """
      class MyClass {
        func 1️⃣myFunc() {}
      }
      """,
      expectedLocations: []
    )
  }

  func testOverrideClassVar() async throws {
    try await testImplementation(
      """
      class MyClass {
        var 1️⃣member: String { "puszysta" }
      }
      class SubclassA: MyClass {
        override var 2️⃣member: String { "glazurowana" }
      }
      class SubclassB: MyClass {
        override var 3️⃣member: String { "piaskowana" }
      }
      """,
      expectedLocations: ["2️⃣", "3️⃣"]
    )
  }

  func testOverrideProtocolFunc() async throws {
    // TODO: We should not be reporting locations 4, 5 and 7 because they don't actually contain myFunc.
    // We should, however, be reporting location 6. (https://github.com/swiftlang/sourcekit-lsp/issues/1600)

    try await testImplementation(
      """
      protocol MyProto {
        func 1️⃣myFunc()
      }

      class ClassA: MyProto {
        func 2️⃣myFunc() {}
      }
      class ClassB: MyProto {
        func 3️⃣myFunc() {}
      }
      class 4️⃣ClassBSubA: ClassB {}
      class 5️⃣ClassBSubB: ClassB {}

      class RetroactiveConformanceClassWithMyFuncInClassDecl {
        func 6️⃣myFunc() { }
      }
      extension 7️⃣RetroactiveConformanceClassWithMyFuncInClassDecl: MyProto {}

      class RetroactiveConformanceClassWithMyFuncInExtension {}
      extension RetroactiveConformanceClassWithMyFuncInExtension: MyProto {
        func 8️⃣myFunc() { }
      }
      """,
      expectedLocations: ["2️⃣", "3️⃣", "4️⃣", "5️⃣", "7️⃣", "8️⃣"]
    )
  }

  func testCrossFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "a.swift": """
        protocol 1️⃣MyProto {}
        """,
        "b.swift": """
        struct MyStruct: 2️⃣MyProto {}
        """,
      ],
      enableBackgroundIndexing: true
    )

    let (aUri, aPositions) = try project.openDocument("a.swift")

    let response = try await project.testClient.send(
      ImplementationRequest(
        textDocument: TextDocumentIdentifier(aUri),
        position: aPositions["1️⃣"]
      )
    )
    guard case .locations(let implementations) = response else {
      XCTFail("Response was not locations")
      return
    }
    XCTAssertEqual(
      implementations,
      [Location(uri: try project.uri(for: "b.swift"), range: Range(try project.position(of: "2️⃣", in: "b.swift")))]
    )
  }
}
