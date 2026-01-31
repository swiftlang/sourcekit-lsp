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

import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKTestSupport
import SKUtilities
import Testing

@Suite(.serialized)
// we have to make the tests run serialized as otherwise we get a deadlock caused by the TestSourceKitLSPClient deinitializer
struct SelectionRangeTests {

  struct StringsAndExpressions {

    @Test
    func testStringLiteralWithCursorInWord() async throws {
      try await testSelectionRange(
        markedSource: """
          let a = "Hel1️⃣lo, World!"
          """,
        expectedSelections: [
          "Hello,",
          "Hello, World!",
          "\"Hello, World!\"",
        ]
      )
    }

    @Test
    func testStringLiteralWithCursorInWhitespace() async throws {
      try await testSelectionRange(
        markedSource: """
          let a = "Hello,1️⃣ World!"
          """,
        expectedSelections: [
          "Hello, World!",
          "\"Hello, World!\"",
          "let a = \"Hello, World!\"",
        ]
      )
    }

    @Test
    func testStringLiteralWithStringInterpolation() async throws {
      try await testSelectionRange(
        markedSource: """
          func a() {
            let a = "Hello \\(w1️⃣o)rld"
          }
          """,
        expectedSelections: [
          "wo",
          "\\(wo)",
          "Hello \\(wo)rld",
        ]
      )
    }

    @Test(arguments: 1...3)
    func testMultipleCursors(cursor: Int) async throws {
      try await testSelectionRange(
        markedSource: """
            let a = "Hel1️⃣lo, World!"
            let b = "Hel2️⃣lo, World!"
            let c = "Hel3️⃣lo, World!"
          """,
        cursor: cursor,
        expectedSelections: [
          ["Hello,", "Hello, World!"],
          ["Hello,", "Hello, World!"],
          ["Hello,", "Hello, World!"],
        ]
      )
    }

    @Test
    func testStringConcatenation() async throws {
      try await testSelectionRange(
        markedSource: """
            let x = "abc" + "def" + "ghi" + "jk1️⃣l" + "mno" + "pqr" + "stu" + "vwx" + "yz"
          """,
        expectedSelections: [
          "jkl",
          "\"jkl\"",
          "\"abc\" + \"def\" + \"ghi\" + \"jkl\"",
          "\"abc\" + \"def\" + \"ghi\" + \"jkl\" + \"mno\"",
          "\"abc\" + \"def\" + \"ghi\" + \"jkl\" + \"mno\" + \"pqr\"",
          "\"abc\" + \"def\" + \"ghi\" + \"jkl\" + \"mno\" + \"pqr\" + \"stu\"",
          "\"abc\" + \"def\" + \"ghi\" + \"jkl\" + \"mno\" + \"pqr\" + \"stu\" + \"vwx\"",
          "\"abc\" + \"def\" + \"ghi\" + \"jkl\" + \"mno\" + \"pqr\" + \"stu\" + \"vwx\" + \"yz\"",
        ]
      )
    }

    @Test
    func testComplexConditionalExpression() async throws {
      try await testSelectionRange(
        markedSource: """
          let valid = (x > 0 && y <1️⃣ 100) || (x == 0 && y == 0)
          """,
        expectedSelections: [
          "<",
          "y < 100",
          "x > 0 && y < 100",
          "(x > 0 && y < 100)",
          "(x > 0 && y < 100) || (x == 0 && y == 0)",
          "let valid = (x > 0 && y < 100) || (x == 0 && y == 0)",
        ]
      )
    }

    @Test
    func testComplexConditionalExpression2() async throws {
      try await testSelectionRange(
        markedSource: """
          let valid = (x > 0 && (y <1️⃣ 100)) || (x == 0 && y == 0)
          """,
        expectedSelections: [
          "<",
          "y < 100",
          "(y < 100)",
          "x > 0 && (y < 100)",
          "(x > 0 && (y < 100))",
          "(x > 0 && (y < 100)) || (x == 0 && y == 0)",
          "let valid = (x > 0 && (y < 100)) || (x == 0 && y == 0)",
        ]
      )
    }
  }

  struct VariableAndConstantDeclaration {

    @Test
    func testSimpleVariableDeclaration() async throws {
      try await testSelectionRange(
        markedSource: """
          var sim1️⃣ple = 42
          """,
        expectedSelections: [
          "simple",
          "var simple = 42",
        ]
      )
    }

    @Test
    func testMultipleBindingsInSingleDeclaration() async throws {
      try await testSelectionRange(
        markedSource: """
          let x = 1, 1️⃣y = 2, z = 3
          """,
        expectedSelections: [
          "y",
          "y = 2",
          "let x = 1, y = 2, z = 3",
        ]
      )
    }

    @Test
    func testVariableWithExplicitType() async throws {
      try await testSelectionRange(
        markedSource: """
          let name: Str1️⃣ing = "Swift"
          """,
        expectedSelections: [
          "String",
          ": String",
          "let name: String = \"Swift\"",
        ]
      )
    }

    @Test
    func testLazyVariable() async throws {
      try await testSelectionRange(
        markedSource: """
          lazy var data = exp1️⃣ensive()
          """,
        expectedSelections: [
          "expensive",
          "expensive()",
          "lazy var data = expensive()",
        ]
      )
    }

    @Test
    func testComputedProperty() async throws {
      try await testSelectionRange(
        markedSource: """
          var fullName: String {
            return first1️⃣Name + " " + lastName
          }
          """,
        expectedSelections: [
          "firstName",
          "firstName + \" \"",
          "firstName + \" \" + lastName",
          "return firstName + \" \" + lastName",
          """
          {
            return firstName + " " + lastName
          }
          """,
          """
          var fullName: String {
            return firstName + " " + lastName
          }
          """,
        ]
      )
    }

    @Test
    func testPropertyWithGetterAndSetter() async throws {
      try await testSelectionRange(
        markedSource: """
          var temperature: Double {
            get {
              return _temp1️⃣erature
            }
            set {
              _temperature = newValue
            }
          }
          """,
        expectedSelections: [
          "_temperature",
          "return _temperature",
          """
          get {
              return _temperature
            }
          """,
        ]
      )
    }

    @Test
    func testPropertyWithWillSetDidSet() async throws {
      try await testSelectionRange(
        markedSource: """
          var count: Int = 0 {
            willSet {
              print("About to set count to \\(new1️⃣Value)")
            }
            didSet {
              print("Changed from \\(oldValue)")
            }
          }
          """,
        expectedSelections: [
          "newValue",
          "\\(newValue)",
          "About to set count to \\(newValue)",
          "\"About to set count to \\(newValue)\"",
          "print(\"About to set count to \\(newValue)\")",
          """
          willSet {
              print("About to set count to \\(newValue)")
            }
          """,
          """
          {
            willSet {
              print("About to set count to \\(newValue)")
            }
            didSet {
              print("Changed from \\(oldValue)")
            }
          }
          """,
          """
          var count: Int = 0 {
            willSet {
              print("About to set count to \\(newValue)")
            }
            didSet {
              print("Changed from \\(oldValue)")
            }
          }
          """,
        ]
      )
    }
  }

  struct FunctionsAndMethods {

    @Test(arguments: 1...3)
    func testChainedMethodCalls(cursor: Int) async throws {
      try await testSelectionRange(
        markedSource: """
          let result = numbers
            .filter { $0 > 1️⃣0 }
            .map { $0 * 2️⃣2 }
            .reduce(0, 3️⃣+)
          """,
        cursor: cursor,
        expectedSelections: [
          [
            "0",
            "$0 > 0",
            "{ $0 > 0 }",
            "filter { $0 > 0 }",
            """
            numbers
              .filter { $0 > 0 }
            """,
            """
            numbers
              .filter { $0 > 0 }
              .map { $0 * 2 }
            """,
            """
            numbers
              .filter { $0 > 0 }
              .map { $0 * 2 }
              .reduce(0, +)
            """,
            """
            let result = numbers
              .filter { $0 > 0 }
              .map { $0 * 2 }
              .reduce(0, +)
            """,
          ],
          [
            "2",
            "$0 * 2",
            "{ $0 * 2 }",
            "map { $0 * 2 }",
            """
            numbers
              .filter { $0 > 0 }
              .map { $0 * 2 }
            """,
            """
            numbers
              .filter { $0 > 0 }
              .map { $0 * 2 }
              .reduce(0, +)
            """,
          ],
          [
            "+",
            "0, +",
            "reduce(0, +)",
            """
            numbers
              .filter { $0 > 0 }
              .map { $0 * 2 }
              .reduce(0, +)
            """,
          ],
        ]
      )
    }

    @Test
    func testNestedFunctionCalls() async throws {
      try await testSelectionRange(
        markedSource: """
          let result = max(min(va1️⃣lue, 100), 0)
          """,
        expectedSelections: [
          "value",
          "value, 100",
          "min(value, 100)",
          "min(value, 100), 0",
          "max(min(value, 100), 0)",
          "let result = max(min(value, 100), 0)",
        ]
      )
    }

    @Test
    func testFunctionCallParameterExplicit() async throws {
      try await testSelectionRange(
        markedSource: """
          func a() {
            b(c, d: 1️⃣320)
          }
          """,
        expectedSelections: [
          "320",
          "d: 320",
          "c, d: 320",
          "b(c, d: 320)",
        ]
      )
    }

    @Test
    func testFunctionCallCursorAfterLastParameter() async throws {
      try await testSelectionRange(
        markedSource: "test(a: 12, b: 31️⃣)",
        expectedSelections: [
          "3",
          "b: 3",
          "a: 12, b: 3",
          "test(a: 12, b: 3)",
        ]
      )
    }

    @Test
    func testFunctionCallWithNoArguments() async throws {
      try await testSelectionRange(
        markedSource: "test(1️⃣)",
        expectedSelections: [
          "test()"
        ]
      )
    }

    @Test
    func testSimpleFunctionDeclarationParameter() async throws {
      try await testSelectionRange(
        markedSource: """
          func greet(nam1️⃣e: String) -> String {
            return "Hello, \\(name)"
          }
          """,
        expectedSelections: [
          "name",
          "name: String",
          """
          func greet(name: String) -> String {
            return "Hello, \\(name)"
          }
          """,
        ]
      )
    }

    @Test
    func testSimpleFunctionDeclarationWithCursorAfterLastParameter() async throws {
      try await testSelectionRange(
        markedSource: "func test(a: Int, b: Int1️⃣) {}",
        expectedSelections: [
          "Int",
          "b: Int",
          "a: Int, b: Int",
        ]
      )
    }

    @Test
    func testSimpleFunctionDeclarationName() async throws {
      try await testSelectionRange(
        markedSource: """
          func gre1️⃣et(name: String) -> String {
            return "Hello, \\(name)"
          }
          """,
        expectedSelections: [
          "greet",
          """
          func greet(name: String) -> String {
            return "Hello, \\(name)"
          }
          """,
        ]
      )
    }

    @Test
    func testFunctionDeclarationWithTwoNameParameter() async throws {
      try await testSelectionRange(
        markedSource: "func test(abc de1️⃣f: String) {}",
        expectedSelections: [
          "def",
          "abc def",
          "abc def: String",
        ]
      )
    }

    @Test
    func testFunctionWithMultipleParameters() async throws {
      try await testSelectionRange(
        markedSource: """
          func calculate(a: Int, b: I1️⃣nt, operation: (Int, Int) -> Int) -> Int {
            return operation(a, b)
          }
          """,
        expectedSelections: [
          "Int",
          "b: Int",
          "a: Int, b: Int, operation: (Int, Int) -> Int",
          """
          func calculate(a: Int, b: Int, operation: (Int, Int) -> Int) -> Int {
            return operation(a, b)
          }
          """,
        ]
      )
    }

    @Test
    func testFunctionWithDefaultParameters() async throws {
      try await testSelectionRange(
        markedSource: """
          func greet(name: String, greeting: String = "Hel1️⃣lo") {
            print("\\(greeting), \\(name)")
          }
          """,
        expectedSelections: [
          "Hello",
          "\"Hello\"",
          "greeting: String = \"Hello\"",
          "name: String, greeting: String = \"Hello\"",
        ]
      )
    }

    @Test
    func testFunctionWithVariadicParameters() async throws {
      try await testSelectionRange(
        markedSource: """
          func sum(numbers: I1️⃣nt...) -> Int {
            return numbers.reduce(0, +)
          }
          """,
        expectedSelections: [
          "Int",
          "Int...",
          "numbers: Int...",
        ]
      )
    }

    @Test
    func testFunctionWithInoutParameter() async throws {
      try await testSelectionRange(
        markedSource: """
          func swap(a: inout In1️⃣t, b: inout Int) {
            let temp = a
            a = b
            b = temp
          }
          """,
        expectedSelections: [
          "Int",
          "inout Int",
          "a: inout Int",
          "a: inout Int, b: inout Int",
        ]
      )
    }

    @Test
    func testReturnType() async throws {
      try await testSelectionRange(
        markedSource: """
          func test() -> Str1️⃣ing {
            return "test"
          }
          """,
        expectedSelections: [
          "String",
          "-> String",
          """
          func test() -> String {
            return "test"
          }
          """,
        ]
      )
    }

    @Test
    func testReturnTypeWithEffects() async throws {
      try await testSelectionRange(
        markedSource: """
          func test() async throws -> Str1️⃣ing {
            return "test"
          }
          """,
        expectedSelections: [
          "String",
          "-> String",
          """
          func test() async throws -> String {
            return "test"
          }
          """,
        ]
      )
    }

    @Test
    func testFunctionWithThrows() async throws {
      try await testSelectionRange(
        markedSource: """
          func processFile() thr1️⃣ows -> String {
            return try readFile()
          }
          """,
        expectedSelections: [
          "throws",
          """
          func processFile() throws -> String {
            return try readFile()
          }
          """,
        ]
      )
    }

    @Test
    func testAsyncFunction() async throws {
      try await testSelectionRange(
        markedSource: """
          func fetchData() as1️⃣ync throws -> Data {
            return try await URLSession.shared.data(from: url)
          }
          """,
        expectedSelections: [
          "async",
          "async throws",
        ]
      )
    }

    @Test
    func testFunctionWithGenericParameter() async throws {
      try await testSelectionRange(
        markedSource: """
          func identity<1️⃣T>(value: T) -> T {
            return value
          }
          """,
        expectedSelections: [
          "T",
          "<T>",
          "identity<T>",
        ]
      )
    }

    @Test
    func testFunctionWithGenericParameterCursorAfterGenericVariable() async throws {
      try await testSelectionRange(
        markedSource: "func test<T1️⃣>() {}",
        expectedSelections: [
          "T",
          "<T>",
          "test<T>",
        ]
      )
    }

    @Test
    func testFunctionWithMultipleGenericParameters() async throws {
      try await testSelectionRange(
        markedSource: """
          func test<T1️⃣, S>(value: T) {}
          """,
        expectedSelections: [
          "T",
          "T, S",
          "<T, S>",
          "test<T, S>",
        ]
      )
    }

    @Test
    func testGenericParametersWithTrailingComma() async throws {
      try await testSelectionRange(
        markedSource: "func test<T,1️⃣>() {}",
        expectedSelections: [
          "T,",
          "<T,>",
          "test<T,>",
        ]
      )
    }

    @Test
    func testGenericParametersWithTrailingComma2() async throws {
      try await testSelectionRange(
        markedSource: "func test<T1️⃣,>() {}",
        expectedSelections: [
          "T,",
          "<T,>",
          "test<T,>",
        ]
      )
    }

    @Test
    func testFunctionWithWhereClause() async throws {
      try await testSelectionRange(
        markedSource: """
          func compare<T>(a: T, b: T) -> Bool where T: Co1️⃣mparable {
            return a < b
          }
          """,
        expectedSelections: [
          "Comparable",
          "T: Comparable",
          "where T: Comparable",
          """
          func compare<T>(a: T, b: T) -> Bool where T: Comparable {
            return a < b
          }
          """,
        ]
      )
    }
  }

  struct ClosuresAndFunctionTypes {

    @Test
    func testSimpleClosure() async throws {
      try await testSelectionRange(
        markedSource: """
          let closure = { (x: Int) -> Int in
            return x * 1️⃣2
          }
          """,
        expectedSelections: [
          "2",
          "x * 2",
          "return x * 2",
          """
          { (x: Int) -> Int in
            return x * 2
          }
          """,
          """
          let closure = { (x: Int) -> Int in
            return x * 2
          }
          """,
        ]
      )
    }

    @Test
    func testTrailingClosure() async throws {
      try await testSelectionRange(
        markedSource: """
          numbers.map { nu1️⃣m in
            return num * 2
          }
          """,
        expectedSelections: [
          "num",
          "num in",
          "num in\n  return num * 2",
          """
          { num in
            return num * 2
          }
          """,
          """
          map { num in
            return num * 2
          }
          """,
        ]
      )
    }

    @Test
    func testShorthandClosureArgument() async throws {
      try await testSelectionRange(
        markedSource: """
          let doubled = numbers.map { $0 1️⃣* 2 }
          """,
        expectedSelections: [
          "*",
          "$0 * 2",
          "{ $0 * 2 }",
          "map { $0 * 2 }",
          "numbers.map { $0 * 2 }",
          "let doubled = numbers.map { $0 * 2 }",
        ]
      )
    }

    @Test
    func testMultipleTrailingClosures() async throws {
      try await testSelectionRange(
        markedSource: """
          loadData { data in
            process(da1️⃣ta)
          } onError: { error in
            print(error)
          }
          """,
        expectedSelections: [
          "data",
          "process(data)",
          """
          { data in
            process(data)
          }
          """,
          """
          loadData { data in
            process(data)
          } onError: { error in
            print(error)
          }
          """,
        ]
      )
    }
  }

  struct ControlFlow {

    @Test
    func testIfStatement() async throws {
      try await testSelectionRange(
        markedSource: """
          if x >1️⃣ 0 {
            print("positive")
          }
          """,
        expectedSelections: [
          ">",
          "x > 0",
          """
          if x > 0 {
            print("positive")
          }
          """,
        ]
      )
    }

    @Test
    func testIfElseStatement() async throws {
      try await testSelectionRange(
        markedSource: """
          if x > 0 {
            print("positive")
          } else {
            print("neg1️⃣ative")
          }
          """,
        expectedSelections: [
          "negative",
          "\"negative\"",
          "print(\"negative\")",
          """
          else {
            print("negative")
          }
          """,
          """
          if x > 0 {
            print("positive")
          } else {
            print("negative")
          }
          """,
        ]
      )
    }

    @Test
    func testGuardStatement() async throws {
      try await testSelectionRange(
        markedSource: """
          guard let va1️⃣lue = optional else {
            return
          }
          """,
        expectedSelections: [
          "value",
          "let value = optional",
          """
          guard let value = optional else {
            return
          }
          """,
        ]
      )
    }

    @Test
    func testSwitchStatement() async throws {
      try await testSelectionRange(
        markedSource: """
          switch value {
          case .option1️⃣1:
            print("one")
          case .option2:
            print("two")
          default:
            break
          }
          """,
        expectedSelections: [
          "option1",
          ".option1",
          "case .option1:\n  print(\"one\")",
          """
          switch value {
          case .option1:
            print("one")
          case .option2:
            print("two")
          default:
            break
          }
          """,
        ]
      )
    }

    @Test
    func testSwitchWithMultipleCases() async throws {
      try await testSelectionRange(
        markedSource: """
          switch value {
          case 1...5, 10.1️⃣..15:
            print("in range")
          default:
            break
          }
          """,
        expectedSelections: [
          "...",
          "10...15",
          "1...5, 10...15",
          "case 1...5, 10...15:\n  print(\"in range\")",
        ]
      )
    }

    @Test
    func testForLoop() async throws {
      try await testSelectionRange(
        markedSource: """
          for i in 1..<1️⃣10 {
            print(i)
          }
          """,
        expectedSelections: [
          "10",
          "1..<10",
          "i in 1..<10",
          """
          for i in 1..<10 {
            print(i)
          }
          """,
        ]
      )
    }

    @Test
    func testWhileLoop() async throws {
      try await testSelectionRange(
        markedSource: """
          while counter <1️⃣ 10 {
            counter += 1
          }
          """,
        expectedSelections: [
          "<",
          "counter < 10",
          """
          while counter < 10 {
            counter += 1
          }
          """,
        ]
      )
    }

    @Test
    func testRepeatWhileLoop() async throws {
      try await testSelectionRange(
        markedSource: """
          repeat {
            counter +1️⃣= 1
          } while counter < 10
          """,
        expectedSelections: [
          "+=",
          "counter += 1",
          """
          repeat {
            counter += 1
          } while counter < 10
          """,
        ]
      )
    }
  }

  struct ClassesAndStructs {

    @Test
    func testClassDeclaration() async throws {
      try await testSelectionRange(
        markedSource: """
          class MyC1️⃣lass: SuperClass, Protocol1 {
            var property: Int = 0
          }
          """,
        expectedSelections: [
          "MyClass",
          """
          class MyClass: SuperClass, Protocol1 {
            var property: Int = 0
          }
          """,
        ]
      )
    }

    @Test func testClassDeclarationInheritance() async throws {
      try await testSelectionRange(
        markedSource: """
          class MyClass: SuperC1️⃣lass, Protocol1, Protocol2 {
            var property: Int = 0
          }
          """,
        expectedSelections: [
          "SuperClass",
          "SuperClass, Protocol1, Protocol2",
          ": SuperClass, Protocol1, Protocol2",
          """
          class MyClass: SuperClass, Protocol1, Protocol2 {
            var property: Int = 0
          }
          """,
        ]
      )
    }

    @Test
    func testStructDeclaration() async throws {
      try await testSelectionRange(
        markedSource: """
          struct Po1️⃣int {
            var x: Double
            var y: Double
          }
          """,
        expectedSelections: [
          "Point",
          """
          struct Point {
            var x: Double
            var y: Double
          }
          """,
        ]
      )
    }

    @Test
    func testClassWithInitializer() async throws {
      try await testSelectionRange(
        markedSource: """
          class Person {
            let name: String
            init(na1️⃣me: String) {
              self.name = name
            }
          }
          """,
        expectedSelections: [
          "name",
          "name: String",
          """
          init(name: String) {
              self.name = name
            }
          """,
        ]
      )
    }

    @Test
    func testDeinitializer() async throws {
      try await testSelectionRange(
        markedSource: """
          class Resource {
            deinit {
              print("Clean1️⃣ing up")
            }
          }
          """,
        expectedSelections: [
          "Cleaning",
          "Cleaning up",
          "\"Cleaning up\"",
          "print(\"Cleaning up\")",
          """
          deinit {
              print("Cleaning up")
            }
          """,
        ]
      )
    }
  }

  struct Enums {

    @Test
    func testSimpleEnum() async throws {
      try await testSelectionRange(
        markedSource: """
          enum Direction {
            case no1️⃣rth
            case south
            case east
            case west
          }
          """,
        expectedSelections: [
          "north",
          "case north",
          """
          enum Direction {
            case north
            case south
            case east
            case west
          }
          """,
        ]
      )
    }

    @Test
    func testEnumWithAssociatedValues() async throws {
      try await testSelectionRange(
        markedSource: """
          enum Result {
            case success(val1️⃣ue: String)
            case failure(Error)
          }
          """,
        expectedSelections: [
          "value",
          "value: String",
          "success(value: String)",
          "case success(value: String)",
          """
          enum Result {
            case success(value: String)
            case failure(Error)
          }
          """,
        ]
      )
    }

    @Test
    func testEnumWithRawValues() async throws {
      try await testSelectionRange(
        markedSource: """
          enum Planet: Int {
            case mercury = 1️⃣1
            case venus = 2
            case earth = 3
          }
          """,
        expectedSelections: [
          "1",
          "mercury = 1",
          "case mercury = 1",
          """
          enum Planet: Int {
            case mercury = 1
            case venus = 2
            case earth = 3
          }
          """,
        ]
      )
    }

    @Test
    func testEnumWithMethods() async throws {
      try await testSelectionRange(
        markedSource: """
          enum CompassPoint {
            case north, south
            func description() -> String {
              switch se1️⃣lf {
              case .north: return "North"
              case .south: return "South"
              }
            }
          }
          """,
        expectedSelections: [
          "self",
          """
          switch self {
              case .north: return "North"
              case .south: return "South"
              }
          """,
          """
          func description() -> String {
              switch self {
              case .north: return "North"
              case .south: return "South"
              }
            }
          """,
        ]
      )
    }
  }

  struct Protocols {

    @Test
    func testProtocolDeclaration() async throws {
      try await testSelectionRange(
        markedSource: """
          protocol Drawable {
            func dra1️⃣w()
          }
          """,
        expectedSelections: [
          "draw",
          "func draw()",
          """
          protocol Drawable {
            func draw()
          }
          """,
        ]
      )
    }

    @Test
    func testProtocolWithAssociatedType() async throws {
      try await testSelectionRange(
        markedSource: """
          protocol Container {
            associatedtype Ite1️⃣m
            func add(item: Item)
          }
          """,
        expectedSelections: [
          "Item",
          "associatedtype Item",
          """
          protocol Container {
            associatedtype Item
            func add(item: Item)
          }
          """,
        ]
      )
    }

    @Test
    func testProtocolInheritance() async throws {
      try await testSelectionRange(
        markedSource: """
          protocol TextRepresentable: CustomString1️⃣Convertible {
            var text: String { get }
          }
          """,
        expectedSelections: [
          "CustomStringConvertible",
          ": CustomStringConvertible",
          """
          protocol TextRepresentable: CustomStringConvertible {
            var text: String { get }
          }
          """,
        ]
      )
    }

    @Test
    func testProtocolInheritance2() async throws {
      try await testSelectionRange(
        markedSource: """
          protocol TextRepr1️⃣esentable: CustomStringConvertible {
            var text: String { get }
          }
          """,
        expectedSelections: [
          "TextRepresentable",
          """
          protocol TextRepresentable: CustomStringConvertible {
            var text: String { get }
          }
          """,
        ]
      )
    }

    @Test func testProtocolInheritance3() async throws {
      try await testSelectionRange(
        markedSource: """
          protocol TextRepresentable: CustomStringConve1️⃣rtible, Protocol2, Protocol3 {
            var text: String { get }
          }
          """,
        expectedSelections: [
          "CustomStringConvertible",
          "CustomStringConvertible, Protocol2, Protocol3",
          ": CustomStringConvertible, Protocol2, Protocol3",
          """
          protocol TextRepresentable: CustomStringConvertible, Protocol2, Protocol3 {
            var text: String { get }
          }
          """,
        ]
      )
    }

    @Test
    func testProtocolComposition() async throws {
      try await testSelectionRange(
        markedSource: """
          func process(item: Codable & Hashab1️⃣le) {
            print(item)
          }
          """,
        expectedSelections: [
          "Hashable",
          "Codable & Hashable",
          "item: Codable & Hashable",
          """
          func process(item: Codable & Hashable) {
            print(item)
          }
          """,
        ]
      )
    }
  }

  struct Extensions {

    @Test
    func testExtension() async throws {
      try await testSelectionRange(
        markedSource: """
          extension St1️⃣ring {
            func reversed() -> String {
              return String(self.reversed())
            }
          }
          """,
        expectedSelections: [
          "String",
          """
          extension String {
            func reversed() -> String {
              return String(self.reversed())
            }
          }
          """,
        ]
      )
    }

    @Test
    func testExtensionWithWhereClause() async throws {
      try await testSelectionRange(
        markedSource: """
          extension Ar1️⃣ray where Element == String {
            var description: String { return "" }
          }
          """,
        expectedSelections: [
          "Array",
          """
          extension Array where Element == String {
            var description: String { return "" }
          }
          """,
        ]
      )
    }

    @Test
    func testExtensionWithConformance() async throws {
      try await testSelectionRange(
        markedSource: """
          extension Array: CustomStr1️⃣ingConvertible where Element: CustomStringConvertible {
            var description: String { return "" }
          }
          """,
        expectedSelections: [
          "CustomStringConvertible",
          ": CustomStringConvertible",
          """
          extension Array: CustomStringConvertible where Element: CustomStringConvertible {
            var description: String { return "" }
          }
          """,
        ]
      )
    }
  }

  struct Generics {

    @Test
    func testGenericStruct() async throws {
      try await testSelectionRange(
        markedSource: """
          struct Stack<Ele1️⃣ment> {
            var items: [Element] = []
          }
          """,
        expectedSelections: [
          "Element",
          "<Element>",
          "Stack<Element>",
          """
          struct Stack<Element> {
            var items: [Element] = []
          }
          """,
        ]
      )
    }

    @Test
    func testGenericFunction() async throws {
      try await testSelectionRange(
        markedSource: "func te1️⃣st<T>() {}",
        expectedSelections: [
          "test",
          "test<T>",
          "func test<T>() {}",
        ]
      )
    }

    @Test
    func testGenericConstraints() async throws {
      try await testSelectionRange(
        markedSource: """
          func findIndex<T>(of value: T, in array: [T]) -> Int? where T: Equat1️⃣able {
            return array.firstIndex(of: value)
          }
          """,
        expectedSelections: [
          "Equatable",
          "T: Equatable",
          "where T: Equatable",
        ]
      )
    }

  }
  struct Operators {

    @Test
    func testCustomOperator() async throws {
      try await testSelectionRange(
        markedSource: "infix operator *1️⃣*: MultiplicationPrecedence",
        expectedSelections: [
          "**",
          "infix operator **: MultiplicationPrecedence",
        ]
      )
    }
  }

  struct ErrorHandling {

    @Test
    func testThrowStatement() async throws {
      try await testSelectionRange(
        markedSource: """
          func validate() throws {
            throw ValidationErr1️⃣or.invalid
          }
          """,
        expectedSelections: [
          "ValidationError",
          "ValidationError.invalid",
          "throw ValidationError.invalid",
          """
          func validate() throws {
            throw ValidationError.invalid
          }
          """,
        ]
      )
    }

    @Test
    func testDoCatchBlock() async throws {
      try await testSelectionRange(
        markedSource: """
          do {
            try riskyOper1️⃣ation()
          } catch {
            print(error)
          }
          """,
        expectedSelections: [
          "riskyOperation",
          "riskyOperation()",
          "try riskyOperation()",
          """
          do {
            try riskyOperation()
          } catch {
            print(error)
          }
          """,
        ]
      )
    }

    @Test
    func testTryOptional() async throws {
      try await testSelectionRange(
        markedSource: """
          let result = try? load1️⃣Data()
          """,
        expectedSelections: [
          "loadData",
          "loadData()",
          "try? loadData()",
          "let result = try? loadData()",
        ]
      )
    }

    @Test
    func testTryForced() async throws {
      try await testSelectionRange(
        markedSource: """
          let result = try! load1️⃣Data()
          """,
        expectedSelections: [
          "loadData",
          "loadData()",
          "try! loadData()",
          "let result = try! loadData()",
        ]
      )
    }
  }

  struct TypeCastingAndChecking {

    @Test
    func testTypeCheck() async throws {
      try await testSelectionRange(
        markedSource: """
          if item is Str1️⃣ing {
            print("It's a string")
          }
          """,
        expectedSelections: [
          "String",
          "item is String",
          """
          if item is String {
            print("It's a string")
          }
          """,
        ]
      )
    }

    @Test
    func testTypeDowncast() async throws {
      try await testSelectionRange(
        markedSource: """
          if let text = item as1️⃣? String {
            print(text)
          }
          """,
        expectedSelections: [
          "as?",
          "item as? String",
          "let text = item as? String",
          """
          if let text = item as? String {
            print(text)
          }
          """,
        ]
      )
    }

    @Test
    func testForcedDowncast() async throws {
      try await testSelectionRange(
        markedSource: """
          let text = item a1️⃣s! String
          """,
        expectedSelections: [
          "as!",
          "item as! String",
          "let text = item as! String",
        ]
      )
    }
  }

  struct OptionalHandling {

    @Test
    func testOptionalBinding() async throws {
      try await testSelectionRange(
        markedSource: """
          if let na1️⃣me = optionalName {
            print(name)
          }
          """,
        expectedSelections: [
          "name",
          "let name = optionalName",
          """
          if let name = optionalName {
            print(name)
          }
          """,
        ]
      )
    }

    @Test
    func testOptionalChaining() async throws {
      try await testSelectionRange(
        markedSource: """
          let count = person?.address?.str1️⃣eet?.count
          """,
        expectedSelections: [
          "street",
          "person?.address?.street",
          "person?.address?.street?.count",
          "let count = person?.address?.street?.count",
        ]
      )
    }

    @Test
    func testNilCoalescing() async throws {
      try await testSelectionRange(
        markedSource: """
          let name = optionalName ??1️⃣ "Default"
          """,
        expectedSelections: [
          "??",
          "optionalName ?? \"Default\"",
          "let name = optionalName ?? \"Default\"",
        ]
      )
    }

    @Test
    func testImplicitlyUnwrappedOptional() async throws {
      try await testSelectionRange(
        markedSource: """
          var assumedString: Str1️⃣ing! = "An implicit string"
          """,
        expectedSelections: [
          "String",
          "String!",
          ": String!",
          "var assumedString: String! = \"An implicit string\"",
        ]
      )
    }
  }

  struct Attributes {

    @Test
    func testAvailableAttribute() async throws {
      try await testSelectionRange(
        markedSource: """
          @available(iOS 1️⃣15, *)
          func modernFeature() {
            print("Modern")
          }
          """,
        expectedSelections: [
          "15",
          "iOS 15",
          "iOS 15, *",
          "@available(iOS 15, *)",
          """
          @available(iOS 15, *)
          func modernFeature() {
            print("Modern")
          }
          """,
        ]
      )
    }

    @Test
    func testDiscardableResultAttribute() async throws {
      try await testSelectionRange(
        markedSource: """
          @discardableRes1️⃣ult
          func compute() -> Int {
            return 42
          }
          """,
        expectedSelections: [
          "@discardableResult",
          """
          @discardableResult
          func compute() -> Int {
            return 42
          }
          """,
        ]
      )
    }

    @Test
    func testEscapingAttribute() async throws {
      try await testSelectionRange(
        markedSource: """
          func perform(completion: @esc1️⃣aping () -> Void) {
            completion()
          }
          """,
        expectedSelections: [
          "@escaping",
          "@escaping () -> Void",
          "completion: @escaping () -> Void",
          """
          func perform(completion: @escaping () -> Void) {
            completion()
          }
          """,
        ],
      )
    }

    @Test
    func testMainActorAttribute() async throws {
      try await testSelectionRange(
        markedSource: """
          @MainAct1️⃣or
          class ViewController {
            func updateUI() { }
          }
          """,
        expectedSelections: [
          "@MainActor",
          """
          @MainActor
          class ViewController {
            func updateUI() { }
          }
          """,
        ]
      )
    }
  }

  struct PatternMatching {

    @Test
    func testEnumCasePattern() async throws {
      try await testSelectionRange(
        markedSource: """
          if case .success(let val1️⃣ue) = result {
            print(value)
          }
          """,
        expectedSelections: [
          "value",
          "let value",
          ".success(let value)",
          "case .success(let value) = result",
          """
          if case .success(let value) = result {
            print(value)
          }
          """,
        ]
      )
    }

    @Test
    func testTuplePattern() async throws {
      try await testSelectionRange(
        markedSource: """
          let (x, 1️⃣y, z) = point
          """,
        expectedSelections: [
          "y",
          "x, y, z",
          "(x, y, z)",
          "let (x, y, z) = point",
        ]
      )
    }

    @Test
    func testWildcardPattern() async throws {
      try await testSelectionRange(
        markedSource: """
          for (_, val1️⃣ue) in dictionary {
            print(value)
          }
          """,
        expectedSelections: [
          "value",
          "_, value",
          "(_, value)",
          "(_, value) in dictionary",
          """
          for (_, value) in dictionary {
            print(value)
          }
          """,
        ]
      )
    }
  }

  struct AccessControl {

    @Test
    func testPrivateModifier() async throws {
      try await testSelectionRange(
        markedSource: """
          private var secr1️⃣et: String = "hidden"
          """,
        expectedSelections: [
          "secret",
          "private var secret: String = \"hidden\"",
        ]
      )
    }

    @Test
    func testPublicModifier() async throws {
      try await testSelectionRange(
        markedSource: """
          public func api1️⃣Method() {
            print("Public API")
          }
          """,
        expectedSelections: [
          "apiMethod",
          """
          public func apiMethod() {
            print("Public API")
          }
          """,
        ]
      )
    }

    @Test
    func testOpenClass() async throws {
      try await testSelectionRange(
        markedSource: """
          open class BaseClass {
            open func overrid1️⃣able() { }
          }
          """,
        expectedSelections: [
          "overridable",
          "open func overridable() { }",
        ]
      )
    }
  }

  struct MemoryManagement {

    @Test
    func testWeakReference() async throws {
      try await testSelectionRange(
        markedSource: """
          weak var dele1️⃣gate: MyDelegate?
          """,
        expectedSelections: [
          "delegate",
          "weak var delegate: MyDelegate?",
        ]
      )
    }

    @Test
    func testUnownedReference() async throws {
      try await testSelectionRange(
        markedSource: """
          unowned let par1️⃣ent: Parent
          """,
        expectedSelections: [
          "parent",
          "unowned let parent: Parent",
        ]
      )
    }
  }

  struct Subscripts {

    @Test
    func testSubscriptDeclaration() async throws {
      try await testSelectionRange(
        markedSource: """
          subscript(ind1️⃣ex: Int) -> Int {
            get { return array[index] }
            set { array[index] = newValue }
          }
          """,
        expectedSelections: [
          "index",
          "index: Int",
          """
          subscript(index: Int) -> Int {
            get { return array[index] }
            set { array[index] = newValue }
          }
          """,
        ]
      )
    }

    @Test
    func testSubscriptUsage() async throws {
      try await testSelectionRange(
        markedSource: """
          let value = matrix[1️⃣2, 3]
          """,
        expectedSelections: [
          "2",
          "2, 3",
          "[2, 3]",
          "matrix[2, 3]",
          "let value = matrix[2, 3]",
        ]
      )
    }
  }

  struct TupleAndArrayOperations {

    @Test
    func testTupleCreation() async throws {
      try await testSelectionRange(
        markedSource: """
          let person = (name: "John", ag1️⃣e: 30)
          """,
        expectedSelections: [
          "age",
          "age: 30",
          "name: \"John\", age: 30",
          "(name: \"John\", age: 30)",
          "let person = (name: \"John\", age: 30)",
        ]
      )
    }

    @Test
    func testArrayLiteral() async throws {
      try await testSelectionRange(
        markedSource: """
          let numbers = [1, 2, 1️⃣3, 4, 5]
          """,
        expectedSelections: [
          "3",
          "1, 2, 3, 4, 5",
          "[1, 2, 3, 4, 5]",
          "let numbers = [1, 2, 3, 4, 5]",
        ]
      )
    }

    @Test
    func testDictionaryLiteral() async throws {
      try await testSelectionRange(
        markedSource: """
          let dict = ["key": "val1️⃣ue", "another": "item"]
          """,
        expectedSelections: [
          "value",
          "\"value\"",
          "\"key\": \"value\"",
          "\"key\": \"value\", \"another\": \"item\"",
          "[\"key\": \"value\", \"another\": \"item\"]",
          "let dict = [\"key\": \"value\", \"another\": \"item\"]",
        ]
      )
    }
  }

  struct Macros {

    @Test
    func testMacroUsage() async throws {
      try await testSelectionRange(
        markedSource: "#warnin1️⃣g(\"This is deprecated\")",
        expectedSelections: [
          "#warning(\"This is deprecated\")"
        ]
      )
    }
  }

  struct ResultBuilder {

    @Test
    func testResultBuilderAttribute() async throws {
      try await testSelectionRange(
        markedSource: """
          @resultBui1️⃣lder
          struct HTMLBuilder {
            static func buildBlock(_ components: String...) -> String {
              return components.joined()
            }
          }
          """,
        expectedSelections: [
          "@resultBuilder",
          """
          @resultBuilder
          struct HTMLBuilder {
            static func buildBlock(_ components: String...) -> String {
              return components.joined()
            }
          }
          """,
        ]
      )
    }
  }

  struct AsyncAwait {

    @Test
    func testAwaitExpression() async throws {
      try await testSelectionRange(
        markedSource: """
          let data = await fetchDa1️⃣ta()
          """,
        expectedSelections: [
          "fetchData",
          "fetchData()",
          "await fetchData()",
          "let data = await fetchData()",
        ]
      )
    }

    @Test
    func testAsyncLet() async throws {
      try await testSelectionRange(
        markedSource: """
          async let image1️⃣ = loadImage()
          """,
        expectedSelections: [
          "image",
          "async let image = loadImage()",
        ]
      )
    }

    @Test
    func testTaskGroup() async throws {
      try await testSelectionRange(
        markedSource: """
          await withTaskGroup(of: Int.self) { gro1️⃣up in
            for i in 1...10 {
              group.addTask { i * 2 }
            }
          }
          """,
        expectedSelections: [
          "group",
          "group in",
          """
          group in
            for i in 1...10 {
              group.addTask { i * 2 }
            }
          """,
          """
          { group in
            for i in 1...10 {
              group.addTask { i * 2 }
            }
          }
          """,
          """
          withTaskGroup(of: Int.self) { group in
            for i in 1...10 {
              group.addTask { i * 2 }
            }
          }
          """,
          """
          await withTaskGroup(of: Int.self) { group in
            for i in 1...10 {
              group.addTask { i * 2 }
            }
          }
          """,
        ]
      )
    }
  }

  struct PropertyWrappers {

    @Test
    func testPropertyWrapperUsage() async throws {
      try await testSelectionRange(
        markedSource: """
          @Published var cou1️⃣nt: Int = 0
          """,
        expectedSelections: [
          "count",
          "@Published var count: Int = 0",
        ]
      )
    }

    @Test
    func testPropertyWrapperDeclaration() async throws {
      try await testSelectionRange(
        markedSource: """
          @propertyWrap1️⃣per
          struct Clamped<Value: Comparable> {
            var wrappedValue: Value
          }
          """,
        expectedSelections: [
          "@propertyWrapper",
          """
          @propertyWrapper
          struct Clamped<Value: Comparable> {
            var wrappedValue: Value
          }
          """,
        ]
      )
    }
  }

  struct KeyPaths {

    @Test
    func testKeyPathExpression() async throws {
      try await testSelectionRange(
        markedSource: """
          let keyPath = \\Person.na1️⃣me
          """,
        expectedSelections: [
          "name",
          "\\Person.name",
          "let keyPath = \\Person.name",
        ]
      )
    }

    @Test
    func testKeyPathSubscript() async throws {
      try await testSelectionRange(
        markedSource: """
          let value = person[keyPath: \\.na1️⃣me]
          """,
        expectedSelections: [
          "name",
          "\\.name",
          "keyPath: \\.name",
          "[keyPath: \\.name]",
          "person[keyPath: \\.name]",
          "let value = person[keyPath: \\.name]",
        ]
      )
    }
  }

  struct DynamicMemberLookup {

    @Test
    func testDynamicMemberLookup() async throws {
      try await testSelectionRange(
        markedSource: """
          @dynamicMembe1️⃣rLookup
          struct JSON {
            subscript(dynamicMember key: String) -> String? { nil }
          }
          """,
        expectedSelections: [
          "@dynamicMemberLookup",
          """
          @dynamicMemberLookup
          struct JSON {
            subscript(dynamicMember key: String) -> String? { nil }
          }
          """,
        ]
      )
    }
  }

  struct TypeAliases {

    @Test
    func testTypeAlias() async throws {
      try await testSelectionRange(
        markedSource: """
          typealias StringDict1️⃣ionary = [String: String]
          """,
        expectedSelections: [
          "StringDictionary",
          "typealias StringDictionary = [String: String]",
        ]
      )
    }

    @Test
    func testGenericTypeAlias() async throws {
      try await testSelectionRange(
        markedSource: """
          typealias Handler<T1️⃣> = (T) -> Void
          """,
        expectedSelections: [
          "T",
          "<T>",
          "Handler<T>",
          "typealias Handler<T> = (T) -> Void",
        ]
      )
    }
  }
}

private func testSelectionRange(
  markedSource: String,
  expectedSelections: [String],
  checkNumberOfSelectionsMatchesExactly: Bool = false,
  sourceLocation: SourceLocation = #_sourceLocation,
) async throws {
  try await testSelectionRange(
    markedSource: markedSource,
    cursor: 1,
    expectedSelections: [expectedSelections],
    checkNumberOfSelectionsMatchesExactly: checkNumberOfSelectionsMatchesExactly,
    sourceLocation: sourceLocation
  )
}

private func testSelectionRange(
  markedSource: String,
  cursor: Int,
  expectedSelections: [[String]],
  checkNumberOfSelectionsMatchesExactly: Bool = false,
  sourceLocation: SourceLocation = #_sourceLocation,
) async throws {
  let (documentPositions, text) = DocumentPositions.extract(from: markedSource)

  // check that all expectedSelections are valid
  try #require(
    expectedSelections.count == documentPositions.allMarkers.count,
    "The number of markers and expected selections differ: \(documentPositions.allMarkers.count) markers vs \(expectedSelections.count) selections",
    sourceLocation: sourceLocation
  )
  let flatMappedSelections = expectedSelections.flatMap { $0 }
  try #require(
    flatMappedSelections.allSatisfy { text.contains($0) },
    "The following expected selections are not contained in the source:\n \(flatMappedSelections.filter { !text.contains($0) }.joined(separator: "\n"))",
    sourceLocation: sourceLocation
  )

  // check the actual returned ranges
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI(for: .swift)
  testClient.openDocument(text, uri: uri)

  let position = documentPositions[documentPositions.allMarkers[cursor - 1]]
  let request = SelectionRangeRequest(textDocument: TextDocumentIdentifier(uri), positions: [position])
  let response: SelectionRangeRequest.Response = try await testClient.send(request)

  let lineTable = LineTable(text)

  let range = response[0]
  let expected = expectedSelections[cursor - 1]

  var numberOfSelectionsReturned = 0
  var currentRange = range
  while true {
    numberOfSelectionsReturned += 1
    guard let parent = currentRange.parent else {
      break
    }
    currentRange = parent
  }

  if checkNumberOfSelectionsMatchesExactly {
    #expect(numberOfSelectionsReturned == expected.count, sourceLocation: sourceLocation)
  } else {
    #expect(numberOfSelectionsReturned >= expected.count, sourceLocation: sourceLocation)
  }

  var rangeIndex = 0
  currentRange = range
  while rangeIndex < expected.count {
    let selectString = getStringOfSelectionRange(lineTable: lineTable, selectionRange: currentRange)
    #expect(
      selectString == expected[rangeIndex],
      selectionRangeMismatchMessage(
        rangeIndex: rangeIndex,
        expected: expected[rangeIndex],
        actual: String(selectString)
      ),
      sourceLocation: sourceLocation
    )

    guard let parent = currentRange.parent else {
      break
    }
    currentRange = parent
    rangeIndex += 1
  }
}

private func selectionRangeMismatchMessage(rangeIndex: Int, expected: String, actual: String) -> Comment {
  let isMultiline = expected.contains("\n") || actual.contains("\n")

  if isMultiline {
    return """
      Selection range mismatch at index \(rangeIndex):

      Expected:
      \(expected)

      Actual:
      \(actual)
      """
  } else {
    return """
      Selection range mismatch at index \(rangeIndex):
        Expected: \(expected)
        Actual:   \(actual)
      """
  }
}

private func getStringOfSelectionRange(lineTable: LineTable, selectionRange: SelectionRange) -> Substring {
  let lowerBoundOffset = lineTable.utf8OffsetOf(
    line: selectionRange.range.lowerBound.line,
    utf16Column: selectionRange.range.lowerBound.utf16index
  )
  let upperBoundOffset = lineTable.utf8OffsetOf(
    line: selectionRange.range.upperBound.line,
    utf16Column: selectionRange.range.upperBound.utf16index
  )

  let lowerBoundIndex = lineTable.content.index(lineTable.content.startIndex, offsetBy: lowerBoundOffset)
  let upperBoundIndex = lineTable.content.index(lineTable.content.startIndex, offsetBy: upperBoundOffset)
  return lineTable.content[lowerBoundIndex..<upperBoundIndex]
}
