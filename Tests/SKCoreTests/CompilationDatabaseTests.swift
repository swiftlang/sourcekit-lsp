//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol
import LSPTestSupport
import SKCore
import TSCBasic
import XCTest

final class CompilationDatabaseTests: XCTestCase {
  func testSplitShellEscapedCommand() {
    func check(_ str: String, _ expected: [String], file: StaticString=#filePath, line: UInt=#line) {
      XCTAssertEqual(splitShellEscapedCommand(str), expected, file: file, line: line)
    }

    check("", [])
    check("    ", [])
    check("a", ["a"])
    check("abc", ["abc"])
    check("a😀c", ["a😀c"])
    check("😀c", ["😀c"])
    check("abc def", ["abc", "def"])
    check("abc    def", ["abc", "def"])

    check("\"", [""])
    check("\"a", ["a"])
    check("\"\"", [""])
    check("\"a\"", ["a"])
    check("\"a\\\"\"", ["a\""])
    check("\"a b c \"", ["a b c "])
    check("\"a \" ", ["a "])
    check("\"a \" b", ["a ", "b"])
    check("\"a \"b", ["a b"])
    check("a\"x \"\"b", ["ax b"])

    check("\'", [""])
    check("\'a", ["a"])
    check("\'\'", [""])
    check("\'a\'", ["a"])
    check("\'a\\\"\'", ["a\\\""])
    check("\'a b c \'", ["a b c "])
    check("\'a \' ", ["a "])
    check("\'a \' b", ["a ", "b"])
    check("\'a \'b", ["a b"])
    check("a\'x \'\'b", ["ax b"])

    check("a\\\\", ["a\\"])
    check("\"a\"bcd\"ef\"\"\"\"g\"", ["abcdefg"])
    check("a'\\b \"c\"'", ["a\\b \"c\""])
  }

  func testEncodeCompDBCommand() {
    // Requires JSONEncoder.OutputFormatting.sortedKeys
    if #available(macOS 10.13, *) {
      func check(_ cmd: CompilationDatabase.Command, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let encoder = JSONEncoder()
        encoder.outputFormatting.insert(.sortedKeys)
        let encodedString = try! String(data: encoder.encode(cmd), encoding: .utf8)
        XCTAssertEqual(encodedString, expected, file: file, line: line)
      }

      check(.init(directory: "a", filename: "b", commandLine: [], output: "c"), """
        {"arguments":[],"directory":"a","file":"b","output":"c"}
        """)
      check(.init(directory: "a", filename: "b", commandLine: ["c", "d"], output: nil), """
        {"arguments":["c","d"],"directory":"a","file":"b"}
        """)
    }
  }

  func testDecodeCompDBCommand() {
    func check(_ str: String, _ expected: CompilationDatabase.Command, file: StaticString = #filePath, line: UInt = #line) {
      let cmd = try! JSONDecoder().decode(CompilationDatabase.Command.self, from: str.data(using: .utf8)!)
      XCTAssertEqual(cmd, expected, file: file, line: line)
    }

    check("""
      {
        "arguments" : [

        ],
        "directory" : "a",
        "file" : "b",
        "output" : "c"
      }
      """, .init(directory: "a", filename: "b", commandLine: [], output: "c"))
    check("""
      {
        "arguments" : [
          "c",
          "d"
        ],
        "directory" : "a",
        "file" : "b"
      }
      """, .init(directory: "a", filename: "b", commandLine: ["c", "d"], output: nil))

    check("""
      {
        "directory":"a",
        "file":"b.cpp",
        "command": "/usr/bin/clang++ -std=c++11 -DFOO b.cpp"
      }
      """, .init(
        directory: "a",
        filename: "b.cpp",
        commandLine: [
          "/usr/bin/clang++",
          "-std=c++11",
          "-DFOO",
          "b.cpp",
        ],
        output: nil
    ))

    XCTAssertThrowsError(try JSONDecoder().decode(CompilationDatabase.Command.self, from: """
      {"directory":"a","file":"b"}
    """.data(using: .utf8)!))
  }

  func testJSONCompilationDatabaseCoding() {
    checkCoding(JSONCompilationDatabase([]), json: """
      [

      ]
      """)
    let db = JSONCompilationDatabase([
      .init(directory: "a", filename: "b", commandLine: [], output: nil),
      .init(directory: "c", filename: "b", commandLine: [], output: nil),
      ])
    checkCoding(db, json: """
      [
        {
          "arguments" : [

          ],
          "directory" : "a",
          "file" : "b"
        },
        {
          "arguments" : [

          ],
          "directory" : "c",
          "file" : "b"
        }
      ]
      """)
  }

  func testJSONCompilationDatabaseLookup() {
    let cmd1 = CompilationDatabase.Command(directory: "a", filename: "b", commandLine: [], output: nil)
    let cmd2 = CompilationDatabase.Command(directory: "/c", filename: "b", commandLine: [], output: nil)
    let cmd3 = CompilationDatabase.Command(directory: "/c", filename: "/b", commandLine: [], output: nil)

    let db = JSONCompilationDatabase([cmd1, cmd2, cmd3])

    XCTAssertEqual(db[URL(fileURLWithPath: "b")], [cmd1])
    XCTAssertEqual(db[URL(fileURLWithPath: "/c/b")], [cmd2])
    XCTAssertEqual(db[URL(fileURLWithPath: "/b")], [cmd3])
  }

  func testJSONCompilationDatabaseFromDirectory() {
    let fs = InMemoryFileSystem()
    try! fs.createDirectory(AbsolutePath("/a"))
    XCTAssertNil(tryLoadCompilationDatabase(directory: AbsolutePath("/a"), fs))

    try! fs.writeFileContents(AbsolutePath("/a/compile_commands.json"), bytes: """
      [
        {
          "file": "/a/a.swift",
          "directory": "/a",
          "arguments": ["swiftc", "/a/a.swift"]
        }
      ]
      """)

    XCTAssertNotNil(tryLoadCompilationDatabase(directory: AbsolutePath("/a"), fs))
  }

  func testCompilationDatabaseBuildSystem() {
    checkCompilationDatabaseBuildSystem("""
    [
      {
        "file": "/a/a.swift",
        "directory": "/a",
        "arguments": ["swiftc", "-swift-version", "4", "/a/a.swift"]
      }
    ]
    """) { buildSystem in
      let settings = buildSystem._settings(for: DocumentURI(URL(fileURLWithPath: "/a/a.swift")))
      XCTAssertNotNil(settings)
      XCTAssertEqual(settings?.workingDirectory, "/a")
      XCTAssertEqual(settings?.compilerArguments, ["-swift-version", "4", "/a/a.swift"])
      XCTAssertNil(buildSystem.indexStorePath)
      XCTAssertNil(buildSystem.indexDatabasePath)
    }
  }

  func testCompilationDatabaseBuildSystemIndexStoreSwift0() {
    checkCompilationDatabaseBuildSystem("[]") { buildSystem in
      XCTAssertNil(buildSystem.indexStorePath)
    }
  }

  func testCompilationDatabaseBuildSystemIndexStoreSwift1() {
    checkCompilationDatabaseBuildSystem("""
    [
      {
        "file": "/a/a.swift",
        "directory": "/a",
        "arguments": ["swiftc", "-swift-version", "4", "/a/a.swift", "-index-store-path", "/b"]
      }
    ]
    """) { buildSystem in
      XCTAssertEqual(URL(fileURLWithPath: buildSystem.indexStorePath?.pathString ?? "").path, "/b")
      XCTAssertEqual(URL(fileURLWithPath: buildSystem.indexDatabasePath?.pathString ?? "").path, "/IndexDatabase")
    }
  }

  func testCompilationDatabaseBuildSystemIndexStoreSwift2() {
    checkCompilationDatabaseBuildSystem("""
    [
      {
        "file": "/a/a.swift",
        "directory": "/a",
        "arguments": ["swiftc", "-swift-version", "4", "/a/a.swift"]
      },
      {
        "file": "/a/b.swift",
        "directory": "/a",
        "arguments": ["swiftc", "-swift-version", "4", "/a/b.swift"]
      },
      {
        "file": "/a/c.swift",
        "directory": "/a",
        "arguments": ["swiftc", "-swift-version", "4", "/a/c.swift", "-index-store-path", "/b"]
      }
    ]
    """) { buildSystem in
      XCTAssertEqual(buildSystem.indexStorePath, AbsolutePath("/b"))
    }
  }

  func testCompilationDatabaseBuildSystemIndexStoreSwift3() {
    checkCompilationDatabaseBuildSystem("""
    [
      {
        "file": "/a/a.swift",
        "directory": "/a",
        "arguments": ["swiftc", "-index-store-path", "/b", "-swift-version", "4", "/a/a.swift"]
      }
    ]
    """) { buildSystem in
      XCTAssertEqual(buildSystem.indexStorePath, AbsolutePath("/b"))
    }
  }

  func testCompilationDatabaseBuildSystemIndexStoreSwift4() {
    checkCompilationDatabaseBuildSystem("""
    [
      {
        "file": "/a/a.swift",
        "directory": "/a",
        "arguments": ["swiftc", "-swift-version", "4", "/a/c.swift", "-index-store-path"]
      }
    ]
    """) { buildSystem in
      XCTAssertNil(buildSystem.indexStorePath)
    }
  }

  func testCompilationDatabaseBuildSystemIndexStoreClang() {
    checkCompilationDatabaseBuildSystem("""
    [
      {
        "file": "/a/a.cpp",
        "directory": "/a",
        "arguments": ["clang", "/a/a.cpp"]
      },
      {
        "file": "/a/b.cpp",
        "directory": "/a",
        "arguments": ["clang", "/a/b.cpp"]
      },
      {
        "file": "/a/c.cpp",
        "directory": "/a",
        "arguments": ["clang", "/a/c.cpp", "-index-store-path", "/b"]
      }
    ]
    """) { buildSystem in
      XCTAssertEqual(URL(fileURLWithPath: buildSystem.indexStorePath?.pathString ?? "").path, "/b")
      XCTAssertEqual(URL(fileURLWithPath: buildSystem.indexDatabasePath?.pathString ?? "").path, "/IndexDatabase")
    }
  }
}

private func checkCompilationDatabaseBuildSystem(_ compdb: ByteString, file: StaticString = #filePath, line: UInt = #line, block: (CompilationDatabaseBuildSystem) -> ()) {
  let fs = InMemoryFileSystem()
  XCTAssertNoThrow(try fs.createDirectory(AbsolutePath("/a")), file: file, line: line)
  XCTAssertNoThrow(try fs.writeFileContents(AbsolutePath("/a/compile_commands.json"), bytes: compdb), file: file, line: line)
  let buildSystem = CompilationDatabaseBuildSystem(projectRoot: AbsolutePath("/a"), fileSystem: fs)
  block(buildSystem)
}
