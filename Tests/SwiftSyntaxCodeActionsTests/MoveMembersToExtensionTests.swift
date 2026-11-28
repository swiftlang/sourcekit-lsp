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

import SKTestSupport
import SwiftParser
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxCodeActions
import XCTest

final class MoveMembersToExtensionTests: XCTestCase {
  func testMoveFunctionFromClass() throws {
    try assertMoveMembersToExtension(
      """
      class Foo {1️⃣
        func foo() {
          print("Hello world!")
        }2️⃣

        func bar() {
          print("Hello world!")
        }
      }
      """,
      expected:
        """
        class Foo {
          func bar() {
            print("Hello world!")
          }
        }

        extension Foo {
          func foo() {
            print("Hello world!")
          }
        }
        """
    )
  }

  func testMoveParticiallySelectedFunctionFromClass() throws {
    try assertMoveMembersToExtension(
      """
      class Foo {
        func foo() {
          1️⃣print("Hello world!")
        }2️⃣

        func bar() {
          print("Hello world!")
        }
      }

      struct Bar {
        func foo() {}
      }
      """,
      expected:
        """
        class Foo {
          func bar() {
            print("Hello world!")
          }
        }

        extension Foo {
          func foo() {
            print("Hello world!")
          }
        }

        struct Bar {
          func foo() {}
        }
        """
    )
  }

  func testMoveSelectedFromClass() throws {
    try assertMoveMembersToExtension(
      """
      class Foo {1️⃣
        func foo() {
          print("Hello world!")
        }

        deinit() {}

        func bar() {
          print("Hello world!")
        }2️⃣
      }

      struct Bar {
        func foo() {}
      }
      """,
      expected:
        """
        class Foo {
          deinit() {}
        }

        extension Foo {
          func foo() {
            print("Hello world!")
          }

          func bar() {
            print("Hello world!")
          }
        }

        struct Bar {
          func foo() {}
        }
        """
    )
  }

  func testMoveNestedFromStruct() throws {
    try assertMoveMembersToExtension(
      """
      struct Outer {1️⃣
        struct Inner {
          func moveThis() {}
        }2️⃣
      }
      """,
      expected:
        """
        struct Outer {
          struct Inner {}
        }

        extension Outer.Inner {
          func moveThis() {}
        }
        """
    )
  }

  func testMoveNestedFromStruct2() throws {
    try assertMoveMembersToExtension(
      """
      struct Outer<T> {1️⃣
        struct Inner {
          func moveThis() {}
        }2️⃣
      }
      """,
      expected:
        """
        struct Outer<T> {
          struct Inner {}
        }

        extension Outer.Inner {
          func moveThis() {}
        }
        """
    )
  }

  func testMoveNestedFunctionNameFromGeneric() throws {
    try assertMoveMembersToExtension(
      """
      struct Outer<T> {
        struct Inner {
          func 1️⃣moveThis()2️⃣ {}
        }
      }
      """,
      expected:
        """
        struct Outer<T> {
          struct Inner {}
        }

        extension Outer.Inner {
          func moveThis() {}
        }
        """
    )
  }

  func testMoveNestedFunctionName2() throws {
    try assertMoveMembersToExtension(
      """
      struct Outer<T> {
        struct Middle {
          struct Inner {
            func 1️⃣moveThis()2️⃣ {}
          }
        }
      }
      """,
      expected:
        """
        struct Outer<T> {
          struct Middle {
            struct Inner {}
          }
        }

        extension Outer.Middle.Inner {
          func moveThis() {}
        }
        """
    )
  }

  func testNestedStoredPropertyIsNotMoved() throws {
    try assertMoveMembersToExtension(
      """
      struct Outer {
        struct Inner {
          1️⃣var value = 12️⃣
        }
      }
      """,
      expected: nil
    )
  }

  func testNestedInvalidMemberRemains() throws {
    try assertMoveMembersToExtension(
      """
      struct Outer {
        struct Inner {1️⃣
          var value = 1

          func moveThis() {}2️⃣
        }
      }
      """,
      expected:
        """
        struct Outer {
          struct Inner {
            var value = 1
          }
        }

        extension Outer.Inner {
          func moveThis() {}
        }
        """
    )
  }

  func testSelectedDeinitializerMember() async throws {
    try assertMoveMembersToExtension(
      """
      class Foo {
        func foo() {
          print("Hello world!")
        }

      1️⃣deinit() {}2️⃣

        func bar() {
          print("Hello world!")
        }
      }

      struct Bar {
        func foo() {}
      }
      """,
      expected: nil
    )
  }

  func testMoveEmptySelection() throws {
    try assertMoveMembersToExtension(
      """
      class Foo {
        func foo() {
          print("Hello world!")
        }
      1️⃣2️⃣
        func bar() {
          print("Hello world!")
        }
      }

      struct Bar {
        func foo() {}
      }
      """,
      expected: nil
    )
  }
}

private func assertMoveMembersToExtension(
  _ source: String,
  expected: SourceFileSyntax?,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  let (markers, source) = extractMarkers(source.description)
  let positions = markers.mapValues { $0 }
  var parser = Parser(source)
  let tree = SourceFileSyntax.parse(from: &parser)

  let range = try XCTUnwrap(positions["1️⃣"])..<XCTUnwrap(positions["2️⃣"])
  let context = MoveMembersToExtension.Context(range: range)

  try assertRefactor(
    tree,
    context: context,
    provider: MoveMembersToExtension.self,
    expected: expected,
    file: file,
    line: line
  )
}
