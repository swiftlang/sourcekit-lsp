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
import XCTest

class SelectionRangeTests: XCTestCase {

  // MARK: - Strings And Expressions

  func testStringLiteralWithCursorInWord() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let a = "Hel1️⃣lo, World!"
        """,
      expectedSelections: [
        "Hello",
        "Hello, World!",
        #""Hello, World!""#,
      ]
    )
  }

  func testStringLiteralWithCursorInWord2() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let a = "Hello, Wor1️⃣ld!"
        """,
      expectedSelections: [
        "World",
        "Hello, World!",
        #""Hello, World!""#,
      ]
    )
  }

  func testStringLiteralWithCursorInWord3() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let a = "Hello, 1️⃣World!"
        """,
      expectedSelections: [
        "World",
        "Hello, World!",
        #""Hello, World!""#,
      ]
    )
  }

  func testStringLiteralWithCursorInWhitespace() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let a = "Hello,1️⃣ World!"
        """,
      expectedSelections: [
        "Hello, World!",
        #""Hello, World!""#,
        #"let a = "Hello, World!""#,
      ]
    )
  }

  func testStringLiteralWithUnicodeChars() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let a = "test 🚀 tes1️⃣t"
        """,
      expectedSelections: ["test", "test 🚀 test", #""test 🚀 test""#]
    )
  }

  func testStringLiteralWithStringInterpolation() async throws {
    try await assertSelectionRanges(
      markedSource: #"""
        func a() {
          let a = "Hello \(w1️⃣o)rld"
        }
        """#,
      expectedSelections: [
        "wo",
        #"\(wo)"#,
        #"Hello \(wo)rld"#,
      ]
    )
  }

  func testStringConcatenation() async throws {
    try await assertSelectionRanges(
      markedSource: """
          let x = "abc" + "def" + "ghi" + "jk1️⃣l" + "mno" + "pqr" + "stu" + "vwx" + "yz"
        """,
      expectedSelections: [
        "jkl",
        #""jkl""#,
        #""abc" + "def" + "ghi" + "jkl""#,
        #""abc" + "def" + "ghi" + "jkl" + "mno""#,
        #""abc" + "def" + "ghi" + "jkl" + "mno" + "pqr""#,
        #""abc" + "def" + "ghi" + "jkl" + "mno" + "pqr" + "stu""#,
        #""abc" + "def" + "ghi" + "jkl" + "mno" + "pqr" + "stu" + "vwx""#,
        #""abc" + "def" + "ghi" + "jkl" + "mno" + "pqr" + "stu" + "vwx" + "yz""#,
      ]
    )
  }

  func testNegativeIntegerLiteral() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let x = -101️⃣0
        """,
      expectedSelections: [
        "100",
        "-100",
        "let x = -100",
      ]
    )
  }

  func testFloatLiteral() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let x = 3.1️⃣5
        """,
      expectedSelections: ["3.5", "let x = 3.5"]
    )
  }

  func testBinaryExpression() async throws {
    try await assertSelectionRanges(
      markedSource: "let a = 3 + 51️⃣",
      expectedSelections: ["5", "3 + 5", "let a = 3 + 5"]
    )
  }

  func testComplexConditionalExpression() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Variable And Constant Declaration

  func testSimpleVariableDeclaration() async throws {
    try await assertSelectionRanges(
      markedSource: """
        var sim1️⃣ple = 42
        """,
      expectedSelections: [
        "simple",
        "var simple = 42",
      ]
    )
  }

  func testMultipleBindingsInSingleDeclaration() async throws {
    try await assertSelectionRanges(
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

  func testVariableWithExplicitType() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let name: Str1️⃣ing = "Swift"
        """,
      expectedSelections: [
        "String",
        ": String",
        #"let name: String = "Swift""#,
      ]
    )
  }

  func testLazyVariable() async throws {
    try await assertSelectionRanges(
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

  func testComputedProperty() async throws {
    try await assertSelectionRanges(
      markedSource: """
        var fullName: String {
          return first1️⃣Name + " " + lastName
        }
        """,
      expectedSelections: [
        "firstName",
        #"firstName + " ""#,
        #"firstName + " " + lastName"#,
        #"return firstName + " " + lastName"#,
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

  func testPropertyWithGetterAndSetter() async throws {
    try await assertSelectionRanges(
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

  func testPropertyWithGetterAndSetterWithCursorInName() async throws {
    try await assertSelectionRanges(
      markedSource: """
        var temp1️⃣erature: Double {
          get {
            return _temperature
          }
        }
        """,
      expectedSelections: [
        "temperature",
        """
        var temperature: Double {
          get {
            return _temperature
          }
        }
        """,
      ]
    )
  }

  func testPropertyWithWillSetDidSet() async throws {
    try await assertSelectionRanges(
      markedSource: #"""
        var count: Int = 0 {
          willSet {
            print("About to set count to \(new1️⃣Value)")
          }
          didSet {
            print("Changed from \(oldValue)")
          }
        }
        """#,
      expectedSelections: [
        "newValue",
        #"\(newValue)"#,
        #"About to set count to \(newValue)"#,
        #""About to set count to \(newValue)""#,
        #"print("About to set count to \(newValue)")"#,
        #"""
        willSet {
            print("About to set count to \(newValue)")
          }
        """#,
        #"""
        {
          willSet {
            print("About to set count to \(newValue)")
          }
          didSet {
            print("Changed from \(oldValue)")
          }
        }
        """#,
        #"""
        var count: Int = 0 {
          willSet {
            print("About to set count to \(newValue)")
          }
          didSet {
            print("Changed from \(oldValue)")
          }
        }
        """#,
      ]
    )
  }

  // MARK: - Functions And Methods

  func testChainedMethodCalls() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let result = numbers
          .filter { $0 > 1️⃣0 }
          .map { $0 * 2️⃣2 }
          .red3️⃣uce(0, 4️⃣+)
        """,
      expectedSelections: [
        "1️⃣": [
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
        "2️⃣": [
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
        "3️⃣": [
          "reduce",
          "reduce(0, +)",
          """
          numbers
            .filter { $0 > 0 }
            .map { $0 * 2 }
            .reduce(0, +)
          """,
        ],
        "4️⃣": [
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

  func testNestedFunctionCalls() async throws {
    try await assertSelectionRanges(
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

  func testFunctionCallParameterExplicit() async throws {
    try await assertSelectionRanges(
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

  func testFunctionCallCursorAfterLastParameter() async throws {
    try await assertSelectionRanges(
      markedSource: "test(a: 12, b: 31️⃣)",
      expectedSelections: [
        "3",
        "b: 3",
        "a: 12, b: 3",
        "test(a: 12, b: 3)",
      ]
    )
  }

  func testFunctionCallWithNoArguments() async throws {
    try await assertSelectionRanges(
      markedSource: "test(1️⃣)",
      expectedSelections: [
        "test()"
      ]
    )
  }

  func testSimpleFunctionDeclarationParameter() async throws {
    try await assertSelectionRanges(
      markedSource: #"""
        func greet(nam1️⃣e: String) -> String {
          return "Hello, \(name)"
        }
        """#,
      expectedSelections: [
        "name",
        "name: String",
        #"""
        func greet(name: String) -> String {
          return "Hello, \(name)"
        }
        """#,
      ]
    )
  }

  func testSimpleFunctionDeclarationWithCursorAfterLastParameter() async throws {
    try await assertSelectionRanges(
      markedSource: "func test(a: Int, b: Int1️⃣) {}",
      expectedSelections: [
        "Int",
        "b: Int",
        "a: Int, b: Int",
      ]
    )
  }

  func testSimpleFunctionDeclarationName() async throws {
    try await assertSelectionRanges(
      markedSource: #"""
        func gre1️⃣et(name: String) -> String {
          return "Hello, \(name)"
        }
        """#,
      expectedSelections: [
        "greet",
        #"""
        func greet(name: String) -> String {
          return "Hello, \(name)"
        }
        """#,
      ]
    )
  }

  func testFunctionDeclarationWithCursorImmediatelyBeforeParenthesis() async throws {
    try await assertSelectionRanges(
      markedSource: "func foo1️⃣(a: Int) {}",
      expectedSelections: ["foo", "func foo(a: Int) {}"]
    )
  }

  func testFunctionDeclarationWithTwoNameParameter() async throws {
    try await assertSelectionRanges(
      markedSource: "func test(abc de1️⃣f: String) {}",
      expectedSelections: [
        "def",
        "abc def",
        "abc def: String",
      ]
    )
  }

  func testFunctionWithMultipleParameters() async throws {
    try await assertSelectionRanges(
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

  func testFunctionWithDefaultParameters() async throws {
    try await assertSelectionRanges(
      markedSource: #"""
        func greet(name: String, greeting: String = "Hel1️⃣lo") {
          print("\(greeting), \(name)")
        }
        """#,
      expectedSelections: [
        "Hello",
        #""Hello""#,
        #"greeting: String = "Hello""#,
        #"name: String, greeting: String = "Hello""#,
      ]
    )
  }

  func testFunctionWithVariadicParameters() async throws {
    try await assertSelectionRanges(
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

  func testFunctionWithInoutParameter() async throws {
    try await assertSelectionRanges(
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

  func testReturnType() async throws {
    try await assertSelectionRanges(
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

  func testReturnTypeWithEffects() async throws {
    try await assertSelectionRanges(
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

  func testFunctionWithThrows() async throws {
    try await assertSelectionRanges(
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

  func testAsyncFunction() async throws {
    try await assertSelectionRanges(
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

  func testFunctionWithGenericParameter() async throws {
    try await assertSelectionRanges(
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

  func testFunctionWithGenericParameterCursorAfterGenericVariable() async throws {
    try await assertSelectionRanges(
      markedSource: "func test<T1️⃣>() {}",
      expectedSelections: [
        "T",
        "<T>",
        "test<T>",
      ]
    )
  }

  func testFunctionWithMultipleGenericParameters() async throws {
    try await assertSelectionRanges(
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

  func testGenericParametersWithTrailingComma() async throws {
    try await assertSelectionRanges(
      markedSource: "func test<T,1️⃣>() {}",
      expectedSelections: [
        "T,",
        "<T,>",
        "test<T,>",
      ]
    )
  }

  func testGenericParametersWithTrailingComma2() async throws {
    try await assertSelectionRanges(
      markedSource: "func test<T1️⃣,>() {}",
      expectedSelections: [
        "T,",
        "<T,>",
        "test<T,>",
      ]
    )
  }

  func testFunctionWithWhereClause() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Closures And Function Types

  func testSimpleClosure() async throws {
    try await assertSelectionRanges(
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

  func testClosureCursorImmediatelyBeforeBrace() async throws {
    try await assertSelectionRanges(
      markedSource: """
          let x = "abc".map 1️⃣{ $0 }
        """,
      expectedSelections: [
        "{ $0 }",
        "map { $0 }",
        #""abc".map { $0 }"#,
        #"let x = "abc".map { $0 }"#,
      ]
    )
  }

  func testTrailingClosure() async throws {
    try await assertSelectionRanges(
      markedSource: """
        numbers.map { nu1️⃣m in
          return num * 2
        }
        """,
      expectedSelections: [
        "num",
        "num in",
        """
        num in
          return num * 2
        """,
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

  func testShorthandClosureArgument() async throws {
    try await assertSelectionRanges(
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

  func testMultipleTrailingClosures() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Control Flow

  func testIfStatement() async throws {
    try await assertSelectionRanges(
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

  func testIfElseStatement() async throws {
    try await assertSelectionRanges(
      markedSource: """
        if x > 0 {
          print("positive")
        } else {
          print("neg1️⃣ative")
        }
        """,
      expectedSelections: [
        "negative",
        #""negative""#,
        #"print("negative")"#,
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

  func testGuardStatement() async throws {
    try await assertSelectionRanges(
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

  func testSwitchStatement() async throws {
    try await assertSelectionRanges(
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
        """
        case .option1:
          print("one")
        """,
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

  func testSwitchWithMultipleCases() async throws {
    try await assertSelectionRanges(
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
        """
        case 1...5, 10...15:
          print("in range")
        """,
      ]
    )
  }

  func testForLoop() async throws {
    try await assertSelectionRanges(
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

  func testForLoopCursorInForKeyword() async throws {
    try await assertSelectionRanges(
      markedSource: "f1️⃣or i in 1...3 {}",
      expectedSelections: ["for", "for i in 1...3 {}"]
    )
  }

  func testWhileLoop() async throws {
    try await assertSelectionRanges(
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

  func testRepeatWhileLoop() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Classes And Structs

  func testClassDeclaration() async throws {
    try await assertSelectionRanges(
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

  func testClassDeclarationInheritance() async throws {
    try await assertSelectionRanges(
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

  func testStructDeclaration() async throws {
    try await assertSelectionRanges(
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

  func testClassWithInitializer() async throws {
    try await assertSelectionRanges(
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

  func testDeinitializer() async throws {
    try await assertSelectionRanges(
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
        #""Cleaning up""#,
        #"print("Cleaning up")"#,
        """
        deinit {
            print("Cleaning up")
          }
        """,
      ]
    )
  }

  // MARK: - Enums

  func testSimpleEnum() async throws {
    try await assertSelectionRanges(
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

  func testEnumWithAssociatedValues() async throws {
    try await assertSelectionRanges(
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

  func testEnumCaseWithTwoNames() async throws {
    try await assertSelectionRanges(
      markedSource: """
          enum Test {
            case caseA(foo b1️⃣ar: String)
            case caseB()
          }
        """,
      expectedSelections: [
        "bar",
        "foo bar",
        "foo bar: String",
        "caseA(foo bar: String)",
      ]
    )
  }

  func testEnumWithRawValues() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Protocols

  func testProtocolDeclaration() async throws {
    try await assertSelectionRanges(
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

  func testProtocolWithAssociatedType() async throws {
    try await assertSelectionRanges(
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

  func testProtocolInheritance() async throws {
    try await assertSelectionRanges(
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

  func testProtocolInheritance2() async throws {
    try await assertSelectionRanges(
      markedSource: """
        protocol TextRepr1️⃣esentable: CustomStringConvertible, Protocol2 {
          var text: String { get }
        }
        """,
      expectedSelections: [
        "TextRepresentable",
        """
        protocol TextRepresentable: CustomStringConvertible, Protocol2 {
          var text: String { get }
        }
        """,
      ]
    )
  }

  func testProtocolComposition() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Extensions

  func testExtensionDeclaration() async throws {
    try await assertSelectionRanges(
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

  func testExtensionWithWhereClause() async throws {
    try await assertSelectionRanges(
      markedSource: """
        extension Array where Ele1️⃣ment == String {
          var description: String { return "" }
        }
        """,
      expectedSelections: [
        "Element",
        "Element == String",
        "where Element == String",
        """
        extension Array where Element == String {
          var description: String { return "" }
        }
        """,
      ]
    )
  }

  func testExtensionWithConformance() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Generics

  func testGenericStruct() async throws {
    try await assertSelectionRanges(
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

  func testGenericStructWithCursorImmediatelyBeforeAngleBracket() async throws {
    try await assertSelectionRanges(
      markedSource: """
        struct Stack1️⃣<Element> {
          var items: [Element] = []
        }
        """,
      expectedSelections: [
        "Stack",
        "Stack<Element>",
        """
        struct Stack<Element> {
          var items: [Element] = []
        }
        """,
      ]
    )
  }

  func testGenericFunction() async throws {
    try await assertSelectionRanges(
      markedSource: "func te1️⃣st<T>() {}",
      expectedSelections: [
        "test",
        "test<T>",
        "func test<T>() {}",
      ]
    )
  }

  func testGenericConstraints() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Operators

  func testCustomOperator() async throws {
    try await assertSelectionRanges(
      markedSource: "infix operator *1️⃣*: MultiplicationPrecedence",
      expectedSelections: [
        "**",
        "infix operator **: MultiplicationPrecedence",
      ]
    )
  }

  // MARK: - Error Handling

  func testThrowStatement() async throws {
    try await assertSelectionRanges(
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

  func testDoCatchBlock() async throws {
    try await assertSelectionRanges(
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

  func testTryOptional() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Type Casting And Checking

  func testTypeCheck() async throws {
    try await assertSelectionRanges(
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

  func testTypeDowncast() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Optional Handling

  func testOptionalBinding() async throws {
    try await assertSelectionRanges(
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

  func testOptionalChaining() async throws {
    try await assertSelectionRanges(
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

  func testNilCoalescing() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let name = optionalName ??1️⃣ "Default"
        """,
      expectedSelections: [
        "??",
        #"optionalName ?? "Default""#,
        #"let name = optionalName ?? "Default""#,
      ]
    )
  }

  func testImplicitlyUnwrappedOptional() async throws {
    try await assertSelectionRanges(
      markedSource: """
        var assumedString: Str1️⃣ing! = "An implicit string"
        """,
      expectedSelections: [
        "String",
        "String!",
        ": String!",
        #"var assumedString: String! = "An implicit string""#,
      ]
    )
  }

  // MARK: - Attributes

  func testAvailableAttribute() async throws {
    try await assertSelectionRanges(
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

  func testDiscardableResultAttribute() async throws {
    try await assertSelectionRanges(
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

  func testEscapingAttribute() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Pattern Matching

  func testEnumCasePattern() async throws {
    try await assertSelectionRanges(
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

  func testTuplePattern() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Access Control

  func testPrivateModifier() async throws {
    try await assertSelectionRanges(
      markedSource: """
        private var secr1️⃣et: String = "hidden"
        """,
      expectedSelections: [
        "secret",
        #"private var secret: String = "hidden""#,
      ]
    )
  }

  // MARK: - Subscripts

  func testSubscriptDeclaration() async throws {
    try await assertSelectionRanges(
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

  func testSubscriptUsage() async throws {
    try await assertSelectionRanges(
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

  func testSubScriptUsageWithCursorImmediatelyBeforeSquare() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let value = matrix1️⃣[2, 3]
        """,
      expectedSelections: [
        "matrix",
        "matrix[2, 3]",
        "let value = matrix[2, 3]",
      ]
    )
  }

  // MARK: - Tuple And Array Operations

  func testTupleCreation() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let person = (name: "John", ag1️⃣e: 30)
        """,
      expectedSelections: [
        "age",
        "age: 30",
        #"name: "John", age: 30"#,
        #"(name: "John", age: 30)"#,
        #"let person = (name: "John", age: 30)"#,
      ]
    )
  }

  func testArrayLiteral() async throws {
    try await assertSelectionRanges(
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

  func testDictionaryLiteral() async throws {
    try await assertSelectionRanges(
      markedSource: """
        let dict = ["key": "val1️⃣ue", "another": "item"]
        """,
      expectedSelections: [
        "value",
        #""value""#,
        #""key": "value""#,
        #""key": "value", "another": "item""#,
        #"["key": "value", "another": "item"]"#,
        #"let dict = ["key": "value", "another": "item"]"#,
      ]
    )
  }

  // MARK: - Macros

  func testMacroUsage() async throws {
    try await assertSelectionRanges(
      markedSource: #"#warnin1️⃣g("This is deprecated")"#,
      expectedSelections: [
        #"#warning("This is deprecated")"#
      ]
    )
  }

  // MARK: - Async Await

  func testAwaitExpression() async throws {
    try await assertSelectionRanges(
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

  func testAsyncLet() async throws {
    try await assertSelectionRanges(
      markedSource: """
        async let image1️⃣ = loadImage()
        """,
      expectedSelections: [
        "image",
        "async let image = loadImage()",
      ]
    )
  }

  func testTaskGroup() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Property Wrappers

  func testPropertyWrapperUsage() async throws {
    try await assertSelectionRanges(
      markedSource: """
        @Published var cou1️⃣nt: Int = 0
        """,
      expectedSelections: [
        "count",
        "@Published var count: Int = 0",
      ]
    )
  }

  // MARK: - Key Paths

  func testKeyPathExpression() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Type Aliases

  func testTypeAlias() async throws {
    try await assertSelectionRanges(
      markedSource: """
        typealias StringDict1️⃣ionary = [String: String]
        """,
      expectedSelections: [
        "StringDictionary",
        "typealias StringDictionary = [String: String]",
      ]
    )
  }

  func testGenericTypeAlias() async throws {
    try await assertSelectionRanges(
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

  // MARK: - Actors

  func testActorDeclaration() async throws {
    try await assertSelectionRanges(
      markedSource: "actor Te1️⃣st {}",
      expectedSelections: ["Test", "actor Test {}"]
    )
  }

  func testActorDeclarationWithGenerics() async throws {
    try await assertSelectionRanges(
      markedSource: "actor Test<T1️⃣> {}",
      expectedSelections: ["T", "<T>", "Test<T>", "actor Test<T> {}"]
    )
  }
}

/// Helper to test selection ranges for a single marker ("1️⃣") in the source.
///
/// - Parameters:
///   - markedSource: The source code string containing a single marker ("1️⃣") indicating the cursor position.
///   - expectedSelections: The expected selection ranges, from innermost to outermost, as strings.
///   - file: The file from which the test is called (default: current file).
///   - line: The line from which the test is called (default: current line).
///
/// This function wraps the multi-marker version for convenience when only one marker is present.
private func assertSelectionRanges(
  markedSource: String,
  expectedSelections: [String],
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  try await assertSelectionRanges(
    markedSource: markedSource,
    expectedSelections: ["1️⃣": expectedSelections],
    file: file,
    line: line
  )
}

/// Helper to test selection ranges for multiple markers in the source.
/// This function extracts marker positions from the source, sends selection range requests, and checks that the returned ranges match the expected selections for each marker.
/// The test does not fail if `expectedSelections` contains less selection ranges than the request returned.
/// This is done to avoid having to always list all selections for all tests.
///
/// - Parameters:
///   - markedSource: The source code string containing one or more markers (e.g., "1️⃣", "2️⃣") indicating cursor positions.
///   - expectedSelections: A dictionary mapping marker strings to arrays of expected selection ranges (from innermost to outermost) as strings.
///   - file: The file from which the test is called (default: current file).
///   - line: The line from which the test is called (default: current line).
private func assertSelectionRanges(
  markedSource: String,
  expectedSelections: [String: [String]],
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let (documentPositions, text) = DocumentPositions.extract(from: markedSource)

  // check that all expectedSelections are valid
  XCTAssertEqual(
    Set(expectedSelections.keys),
    Set(documentPositions.allMarkers),
    "The markers used in the source differ from those in the expected selections. Source: \(documentPositions.allMarkers) Expected: \(expectedSelections.keys)",
    file: file,
    line: line
  )
  let flatMappedSelections = expectedSelections.values.flatMap { $0 }
  XCTAssert(
    flatMappedSelections.allSatisfy { text.contains($0) },
    """
    The following expected selections are not contained in the source:
    \(flatMappedSelections.filter { !text.contains($0) }.joined(separator: "\n"))
    """,
    file: file,
    line: line
  )

  // check the actual returned ranges
  let testClient = try await TestSourceKitLSPClient()
  let uri = DocumentURI(for: .swift)
  testClient.openDocument(text, uri: uri)

  for marker in documentPositions.allMarkers {
    let position = documentPositions[marker]
    let response = try await testClient.send(
      SelectionRangeRequest(textDocument: TextDocumentIdentifier(uri), positions: [position])
    )

    let lineTable = LineTable(text)

    let range = response.first ?? nil
    let expected = expectedSelections[marker] ?? []

    var rangeIndex = 0
    var currentRange: SelectionRange? = range
    while rangeIndex < expected.count {
      let selectString = getStringOfSelectionRange(lineTable: lineTable, selectionRange: currentRange)
      XCTAssertEqual(
        selectString,
        expected[rangeIndex],
        selectionRangeMismatchMessage(
          marker: marker,
          expected: expected[rangeIndex],
          actual: String(selectString)
        ),
        file: file,
        line: line
      )

      currentRange = currentRange?.parent
      rangeIndex += 1
    }
  }
}

private func selectionRangeMismatchMessage(marker: String, expected: String, actual: String) -> String {
  let isMultiline = expected.contains("\n") || actual.contains("\n")

  if isMultiline {
    return """
      Selection range mismatch for marker \(marker):

      Expected:
      \(expected)

      Actual:
      \(actual)
      """
  } else {
    return """
      Selection range mismatch for marker \(marker):
        Expected: \(expected)
        Actual:   \(actual)
      """
  }
}

private func getStringOfSelectionRange(lineTable: LineTable, selectionRange: SelectionRange?) -> String {
  guard let selectionRange = selectionRange else {
    return "<no selection range>"
  }

  let lowerBoundIndex = lineTable.stringIndexOf(
    line: selectionRange.range.lowerBound.line,
    utf16Column: selectionRange.range.lowerBound.utf16index
  )
  let upperBoundIndex = lineTable.stringIndexOf(
    line: selectionRange.range.upperBound.line,
    utf16Column: selectionRange.range.upperBound.utf16index
  )

  return String(lineTable.content[lowerBoundIndex..<upperBoundIndex])
}
