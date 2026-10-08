//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import XCTest

final class WorkspaceMembersTests: SourceKitLSPTestCase {
  func testMembersInTypeAndExtension() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct MyStruct {
        var 1️⃣x: Int
        func 2️⃣foo(a: Int) {}
      }
      extension MyStruct {
        func 3️⃣bar() {}
      }
      """
    )
    let members = try await project.testClient.send(
      WorkspaceMembersRequest(symbol: SourceKitSymbolIdentifier(usr: "s:4test8MyStructV", uri: project.fileURI))
    )
    XCTAssertEqual(
      members,
      [
        SourceKitSymbolMember(
          name: "x",
          kind: .property,
          location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
          symbol: SourceKitSymbolIdentifier(usr: "s:4test8MyStructV1xSivp", uri: project.fileURI)
        ),
        SourceKitSymbolMember(
          name: "foo(a:)",
          kind: .method,
          location: Location(uri: project.fileURI, range: Range(project.positions["2️⃣"])),
          symbol: SourceKitSymbolIdentifier(usr: "s:4test8MyStructV3foo1aySi_tF", uri: project.fileURI)
        ),
        SourceKitSymbolMember(
          name: "bar()",
          kind: .method,
          location: Location(uri: project.fileURI, range: Range(project.positions["3️⃣"])),
          symbol: SourceKitSymbolIdentifier(usr: "s:4test8MyStructV3baryyF", uri: project.fileURI)
        ),
      ]
    )
  }

  func testMembersInExtensionInOtherFile() async throws {
    let project = try await SwiftPMTestProject(
      files: [
        "Container.swift": """
        struct Container {
          func 1️⃣foo() {}
        }
        """,
        "Extension.swift": """
        extension Container {
          func 2️⃣bar() {}
        }
        """,
      ],
      enableBackgroundIndexing: true
    )
    let containerURI = try project.uri(for: "Container.swift")
    let extensionURI = try project.uri(for: "Extension.swift")

    let members = try await project.testClient.send(
      WorkspaceMembersRequest(symbol: SourceKitSymbolIdentifier(usr: "s:9MyLibrary9ContainerV", uri: containerURI))
    )
    XCTAssertEqual(members.map(\.name), ["foo()", "bar()"])
    XCTAssertEqual(
      members.map(\.location),
      [
        Location(uri: containerURI, range: Range(try project.position(of: "1️⃣", in: "Container.swift"))),
        Location(uri: extensionURI, range: Range(try project.position(of: "2️⃣", in: "Extension.swift"))),
      ]
    )
  }

  func testProtocolRequirementsAndExtensionMembers() async throws {
    // A requirement and its default implementation are separate symbols, so both are listed.
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      protocol Q {}
      protocol P {
        var 1️⃣value: Int { get }
        func 2️⃣foo()
      }
      extension P {
        func 3️⃣foo() {}
        func 4️⃣helper() {}
      }
      extension P where Self: Q {
        func 5️⃣constrained() {}
      }
      """
    )
    let members = try await project.testClient.send(
      WorkspaceMembersRequest(symbol: SourceKitSymbolIdentifier(usr: "s:4test1PP", uri: project.fileURI))
    )
    XCTAssertEqual(
      members,
      [
        SourceKitSymbolMember(
          name: "value",
          kind: .property,
          location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
          symbol: SourceKitSymbolIdentifier(usr: "s:4test1PP5valueSivp", uri: project.fileURI)
        ),
        SourceKitSymbolMember(
          name: "foo()",
          kind: .method,
          location: Location(uri: project.fileURI, range: Range(project.positions["2️⃣"])),
          symbol: SourceKitSymbolIdentifier(usr: "s:4test1PP3fooyyF", uri: project.fileURI)
        ),
        SourceKitSymbolMember(
          name: "foo()",
          kind: .method,
          location: Location(uri: project.fileURI, range: Range(project.positions["3️⃣"])),
          symbol: SourceKitSymbolIdentifier(usr: "s:4test1PPAAE3fooyyF", uri: project.fileURI)
        ),
        SourceKitSymbolMember(
          name: "helper()",
          kind: .method,
          location: Location(uri: project.fileURI, range: Range(project.positions["4️⃣"])),
          symbol: SourceKitSymbolIdentifier(usr: "s:4test1PPAAE6helperyyF", uri: project.fileURI)
        ),
        SourceKitSymbolMember(
          name: "constrained()",
          kind: .method,
          location: Location(uri: project.fileURI, range: Range(project.positions["5️⃣"])),
          symbol: SourceKitSymbolIdentifier(usr: "s:4test1PPA2A1QRzrlE11constrainedyyF", uri: project.fileURI)
        ),
      ]
    )
  }

  func testStaticAndClassMembersAreTagged() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      class MyClass {
        func instanceMethod() {}
        var instanceProperty: Int { 0 }
        static func staticMethod() {}
        static var staticProperty: Int { 0 }
        class func classMethod() {}
        class var classProperty: Int { 0 }
      }
      """
    )
    let members = try await project.testClient.send(
      WorkspaceMembersRequest(symbol: SourceKitSymbolIdentifier(usr: "s:4test7MyClassC", uri: project.fileURI))
    )
    XCTAssertEqual(
      members.map(\.name),
      ["instanceMethod()", "instanceProperty", "staticMethod()", "staticProperty", "classMethod()", "classProperty"]
    )
    XCTAssertEqual(members.map(\.tags), [nil, nil, [.static], [.static], [.class], [.class]])
  }

  func testImplicitMembersAreExcluded() async throws {
    // The memberwise initializer `init(x:)` is indexed as an implicit member.
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct MyStruct {
        var 1️⃣x: Int
      }
      """
    )
    let members = try await project.testClient.send(
      WorkspaceMembersRequest(symbol: SourceKitSymbolIdentifier(usr: "s:4test8MyStructV", uri: project.fileURI))
    )
    XCTAssertEqual(members.map(\.name), ["x"])
    XCTAssertEqual(members.map(\.location.range.lowerBound), [project.positions["1️⃣"]])
  }

  func testNestedTypeIsListedWithoutItsMembers() async throws {
    let project = try await IndexedSingleSwiftFileTestProject(
      """
      struct Outer {
        struct 1️⃣Inner {
          func foo() {}
        }
      }
      """
    )
    let members = try await project.testClient.send(
      WorkspaceMembersRequest(symbol: SourceKitSymbolIdentifier(usr: "s:4test5OuterV", uri: project.fileURI))
    )
    XCTAssertEqual(
      members,
      [
        SourceKitSymbolMember(
          name: "Inner",
          kind: .struct,
          location: Location(uri: project.fileURI, range: Range(project.positions["1️⃣"])),
          symbol: SourceKitSymbolIdentifier(usr: "s:4test5OuterV5InnerV", uri: project.fileURI)
        )
      ]
    )
  }
}
