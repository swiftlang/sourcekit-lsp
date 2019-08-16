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

import XCTest
import LanguageServerProtocol
import SKTestSupport

final class CodingTests: XCTestCase {

  func testValueCoding() {
    let url = URL(fileURLWithPath: "/foo.swift")
    // The \\/\\/\\/ is escaping file:// + /foo.swift, which is silly but allowed by json.
    let urljson = "file:\\/\\/\\/foo.swift"

    let range = Position(line: 5, utf16index: 23) ..< Position(line: 6, utf16index: 0)
    // Range.lowerBound -> start, Range.upperBound -> end
    let rangejson = """
      {
        "end" : {
          "character" : 0,
          "line" : 6
        },
        "start" : {
          "character" : 23,
          "line" : 5
        }
      }
      """

    let indent2rangejson = rangejson.indented(2, skipFirstLine: true)

    checkCoding(PositionRange(range), json: rangejson)

    // url -> uri
    checkCoding(Location(url: url, range: range), json: """
      {
        "range" : \(indent2rangejson),
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(TextEdit(range: range, newText: "foo"), json: """
      {
        "newText" : "foo",
        "range" : \(indent2rangejson)
      }
      """)

    // url -> uri
    checkCoding(TextDocumentIdentifier(url), json: """
      {
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(VersionedTextDocumentIdentifier(url, version: nil), json: """
      {
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(VersionedTextDocumentIdentifier(url, version: 3), json: """
      {
        "uri" : "\(urljson)",
        "version" : 3
      }
      """)

    checkCoding(TextDocumentEdit(textDocument: VersionedTextDocumentIdentifier(url, version: 1), edits: [TextEdit(range: range, newText: "foo")]), json: """
      {
        "edits" : [
          {
            "newText" : "foo",
            "range" : \(rangejson.indented(6, skipFirstLine: true))
          }
        ],
        "textDocument" : {
          "uri" : "\(urljson)",
          "version" : 1
        }
      }
      """)

    // url -> uri
    checkCoding(WorkspaceFolder(url: url, name: "foo"), json: """
      {
        "name" : "foo",
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(WorkspaceFolder(url: url), json: """
      {
        "name" : "foo.swift",
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(WorkspaceFolder(url: url, name: ""), json: """
      {
        "name" : "unknown_workspace",
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(MarkupKind.markdown, json: "\"markdown\"")
    checkCoding(MarkupKind.plaintext, json: "\"plaintext\"")

    checkCoding(SymbolKind.file, json: "1")
    checkCoding(SymbolKind.class, json: "5")

    checkCoding(CompletionItemKind.text, json: "1")
    checkCoding(CompletionItemKind.class, json: "7")

    checkCoding(CodeActionKind.quickFix, json: "\"quickfix\"")
    checkCoding(CodeActionKind(rawValue: "x"), json: "\"x\"")

    checkCoding(ErrorCode.cancelled, json: "-32800")

    checkCoding(ClientCapabilities(workspace: nil, textDocument: nil), json: "{\n\n}")

    checkCoding(
      ClientCapabilities(
        workspace: with(WorkspaceClientCapabilities()) { $0.applyEdit = true },
        textDocument: nil),
      json: """
      {
        "workspace" : {
          "applyEdit" : true
        }
      }
      """)

    checkCoding(
      WorkspaceSettingsChange.clangd(ClangWorkspaceSettings(compilationDatabasePath: nil)),
      json: "{\n\n}")
    checkCoding(
      WorkspaceSettingsChange.clangd(ClangWorkspaceSettings(compilationDatabasePath: "foo")),
      json: """
      {
        "compilationDatabasePath" : "foo"
      }
      """)

    // FIXME: should probably be "unknown"; see comment in WorkspaceSettingsChange decoder.
    checkDecoding(json: """
      {
        "hi": "there"
      }
      """, expected: WorkspaceSettingsChange.clangd(ClangWorkspaceSettings(compilationDatabasePath: nil)))

    // experimental can be anything
    checkDecoding(json: """
      {
        "experimenal": [1]
      }
      """, expected: ClientCapabilities(workspace: nil, textDocument: nil))

    checkDecoding(json: """
      {
        "workspace": {
          "workspaceEdit": {
            "documentChanges": false
          }
        }
      }
      """, expected: ClientCapabilities(
        workspace: with(WorkspaceClientCapabilities()) {
          $0.workspaceEdit = WorkspaceClientCapabilities.WorkspaceEdit(documentChanges: false)
        },
        textDocument: nil))

    // ignore unknown keys
    checkDecoding(json: """
      {
        "workspace": {
          "workspaceEdit": {
            "ben's unlikley opton": false
          }
        }
      }
      """, expected: ClientCapabilities(
        workspace: with(WorkspaceClientCapabilities()) {
          $0.workspaceEdit = WorkspaceClientCapabilities.WorkspaceEdit(documentChanges: nil)
        },
        textDocument: nil))

    checkCoding(RequestID.number(100), json: "100")
    checkCoding(RequestID.string("100"), json: "\"100\"")

    checkCoding(Language.c, json: "\"c\"")
    checkCoding(Language.cpp, json: "\"cpp\"")
    checkCoding(Language.objective_c, json: "\"objective-c\"")
    checkCoding(Language.objective_cpp, json: "\"objective-cpp\"")
    checkCoding(Language.swift, json: "\"swift\"")
    checkCoding(Language(rawValue: "unknown"), json: "\"unknown\"")

    checkCoding(DiagnosticCode.number(123), json: "123")
    checkCoding(DiagnosticCode.string("hi"), json: "\"hi\"")
  }
}

func with<T>(_ value: T, mutate: (inout T) -> Void) -> T {
  var localCopy = value
  mutate(&localCopy)
  return localCopy
}

extension String {
  func indented(_ spaces: Int, skipFirstLine: Bool = false) -> String {
    let ws = String(repeating: " ", count: spaces)
    return (skipFirstLine ? "" : ws) + self.replacingOccurrences(of: "\n", with: "\n" + ws)
  }
}
