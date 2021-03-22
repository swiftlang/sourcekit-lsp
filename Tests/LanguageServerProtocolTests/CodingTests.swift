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

import XCTest
import LanguageServerProtocol
import LSPTestSupport

final class CodingTests: XCTestCase {

  func testValueCoding() {
    let url = URL(fileURLWithPath: "/foo.swift")
    let uri = DocumentURI(url)
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

    // url -> uri
    checkCoding(Location(uri: uri, range: range), json: """
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
    checkCoding(TextDocumentIdentifier(uri), json: """
      {
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(VersionedTextDocumentIdentifier(uri, version: nil), json: """
      {
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(VersionedTextDocumentIdentifier(uri, version: 3), json: """
      {
        "uri" : "\(urljson)",
        "version" : 3
      }
      """)

    checkCoding(TextDocumentEdit(textDocument: VersionedTextDocumentIdentifier(uri, version: 1), edits: [TextEdit(range: range, newText: "foo")]), json: """
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
    checkCoding(WorkspaceFolder(uri: uri, name: "foo"), json: """
      {
        "name" : "foo",
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(WorkspaceFolder(uri: uri), json: """
      {
        "name" : "foo.swift",
        "uri" : "\(urljson)"
      }
      """)

    checkCoding(WorkspaceFolder(uri: uri, name: ""), json: """
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

    checkCoding(CodeDescription(href: DocumentURI(string: "file:///some/path")), json: """
    {
      "href" : "file:\\/\\/\\/some\\/path"
    }
    """)

    let markup = MarkupContent(kind: .plaintext, value: "a")
    checkCoding(HoverResponse(contents: .markupContent(markup), range: nil), json: """
      {
        "contents" : {
          "kind" : "plaintext",
          "value" : "a"
        }
      }
      """)

    checkDecoding(json: """
    {
      "contents" : "test"
    }
    """, expected: HoverResponse(contents: .markedStrings([.markdown(value: "test")]), range: nil))

    checkCoding(HoverResponse(contents: .markedStrings([.markdown(value: "test"), .codeBlock(language: "swift", value: "let foo = 2")]), range: nil), json: """
      {
        "contents" : [
          "test",
          {
            "language" : "swift",
            "value" : "let foo = 2"
          }
        ]
      }
      """)

    checkCoding(HoverResponse(contents: .markupContent(markup), range: range), json: """
      {
        "contents" : {
          "kind" : "plaintext",
          "value" : "a"
        },
        "range" : \(rangejson.indented(2, skipFirstLine: true))
      }
      """)

    checkCoding(TextDocumentContentChangeEvent(text: "a"), json: """
      {
        "text" : "a"
      }
      """)
    checkCoding(TextDocumentContentChangeEvent(range: range, rangeLength: 10, text: "a"), json: """
      {
        "range" : \(rangejson.indented(2, skipFirstLine: true)),
        "rangeLength" : 10,
        "text" : "a"
      }
      """)
    checkCoding(WorkspaceEdit(changes: [uri: []]), json: """
      {
        "changes" : {
          "\(urljson)" : [

          ]
        }
      }
      """)

    checkCoding(CompletionList(isIncomplete: true, items: [CompletionItem(label: "abc", kind: .function)]), json: """
      {
        "isIncomplete" : true,
        "items" : [
          {
            "kind" : 3,
            "label" : "abc"
          }
        ]
      }
      """)

    checkDecoding(json: """
      [
        {
          "kind" : 3,
          "label" : "abc"
        }
      ]
      """, expected: CompletionList(isIncomplete: false, items: [CompletionItem(label: "abc", kind: .function)]))

    checkCoding(CompletionItemDocumentation.markupContent(MarkupContent(kind: .markdown, value: "some **Markdown***")), json: """
      {
        "kind" : "markdown",
        "value" : "some **Markdown***"
      }
      """)

    checkCoding(CompletionItemDocumentation.string("Some documentation"), json: """
      "Some documentation"
      """)

    checkCoding(LocationsOrLocationLinksResponse.locations([Location(uri: uri, range: range)]), json: """
      [
        {
          "range" : \(rangejson.indented(4, skipFirstLine: true)),
          "uri" : "\(urljson)"
        }
      ]
      """)

    checkCoding(LocationsOrLocationLinksResponse.locationLinks([LocationLink(targetUri: uri, targetRange: range, targetSelectionRange: range)]), json: """
      [
        {
          "targetRange" : \(rangejson.indented(4, skipFirstLine: true)),
          "targetSelectionRange" : \(rangejson.indented(4, skipFirstLine: true)),
          "targetUri" : "\(urljson)"
        }
      ]
      """)

    checkDecoding(json: """
      {
        "range" : \(rangejson.indented(2, skipFirstLine: true)),
        "uri" : "\(urljson)"
      }
      """, expected: LocationsOrLocationLinksResponse.locations([Location(uri: uri, range: range)]))

    checkCoding(DocumentSymbolResponse.documentSymbols([DocumentSymbol(name: "mySymbol", kind: .function, range: range, selectionRange: range)]), json: """
      [
        {
          "kind" : 12,
          "name" : "mySymbol",
          "range" : \(rangejson.indented(4, skipFirstLine: true)),
          "selectionRange" : \(rangejson.indented(4, skipFirstLine: true))
        }
      ]
      """)

    checkCoding(DocumentSymbolResponse.symbolInformation([SymbolInformation(name: "mySymbol", kind: .function, location: Location(uri: uri, range: range))]), json: """
      [
        {
          "kind" : 12,
          "location" : {
            "range" : \(rangejson.indented(6, skipFirstLine: true)),
            "uri" : "\(urljson)"
          },
          "name" : "mySymbol"
        }
      ]
      """)

    checkCoding(ValueOrBool.value(5), json: "5")
    checkCoding(ValueOrBool<Int>.bool(false), json: "false")

    checkDecoding(json: "2", expected: TextDocumentSyncOptions(openClose: nil, change: .incremental, willSave: nil, willSaveWaitUntil: nil, save: nil))

    checkCoding(TextDocumentSyncOptions(), json: """
      {
        "change" : 2,
        "openClose" : true,
        "save" : {
          "includeText" : false
        },
        "willSave" : true,
        "willSaveWaitUntil" : false
      }
      """)
    
    checkCoding(WorkspaceEdit(documentChanges: [.textDocumentEdit(TextDocumentEdit(textDocument: VersionedTextDocumentIdentifier(uri, version: 2), edits: []))]), json: """
      {
        "documentChanges" : [
          {
            "edits" : [

            ],
            "textDocument" : {
              "uri" : "\(urljson)",
              "version" : 2
            }
          }
        ]
      }
      """)
    checkCoding(WorkspaceEdit(documentChanges: [.createFile(CreateFile(uri: uri))]), json: """
    {
      "documentChanges" : [
        {
          "kind" : "create",
          "uri" : "\(urljson)"
        }
      ]
    }
    """)
    checkCoding(WorkspaceEdit(documentChanges: [.renameFile(RenameFile(oldUri: uri, newUri: uri))]), json: """
    {
      "documentChanges" : [
        {
          "kind" : "rename",
          "newUri" : "\(urljson)",
          "oldUri" : "\(urljson)"
        }
      ]
    }
    """)
    checkCoding(WorkspaceEdit(documentChanges: [.deleteFile(DeleteFile(uri: uri))]), json: """
    {
      "documentChanges" : [
        {
          "kind" : "delete",
          "uri" : "\(urljson)"
        }
      ]
    }
    """)


  }

  func testValueOrBool() {
    XCTAssertTrue(ValueOrBool.value(5).isSupported)
    XCTAssertTrue(ValueOrBool.value(0).isSupported)
    XCTAssertTrue(ValueOrBool<Int>.bool(true).isSupported)
    XCTAssertFalse(ValueOrBool<Int>.bool(false).isSupported)
  }

  func testPositionRange() {
    struct WithPosRange: Codable, Equatable {
      @CustomCodable<PositionRange>
      var range: Range<Position>
    }

    let range = Position(line: 5, utf16index: 23) ..< Position(line: 6, utf16index: 0)
    checkCoding(WithPosRange(range: range), json: """
      {
        "range" : {
          "end" : {
            "character" : 0,
            "line" : 6
          },
          "start" : {
            "character" : 23,
            "line" : 5
          }
        }
      }
      """)
  }

  func testPositionRangeArray() {
    struct WithPosRangeArray: Codable, Equatable {
      @CustomCodable<PositionRangeArray>
      var ranges: [Range<Position>]
    }
    let ranges = [
      Position(line: 1, utf16index: 0) ..< Position(line: 1, utf16index: 10),
      Position(line: 2, utf16index: 2) ..< Position(line: 3, utf16index: 0),
      Position(line: 70, utf16index: 8) ..< Position(line: 70, utf16index: 11)
    ]

    checkCoding(WithPosRangeArray(ranges: ranges), json: """
      {
        "ranges" : [
          {
            "end" : {
              "character" : 10,
              "line" : 1
            },
            "start" : {
              "character" : 0,
              "line" : 1
            }
          },
          {
            "end" : {
              "character" : 0,
              "line" : 3
            },
            "start" : {
              "character" : 2,
              "line" : 2
            }
          },
          {
            "end" : {
              "character" : 11,
              "line" : 70
            },
            "start" : {
              "character" : 8,
              "line" : 70
            }
          }
        ]
      }
      """)
  }

  func testCallHierarchyIncomingCallRanges() {
    let url = URL(fileURLWithPath: "/foo.swift")
    let uri = DocumentURI(url)

    let item = CallHierarchyItem(
      name: "test",
      kind: SymbolKind.method,
      tags: nil,
      uri: uri,
      range: Position(line: 1, utf16index: 0) ..< Position(line: 2, utf16index: 5),
      selectionRange: Position(line: 1, utf16index: 0) ..< Position(line: 1, utf16index: 7)
    )
    let call = CallHierarchyIncomingCall(from: item, fromRanges: [
      Position(line: 2, utf16index: 0) ..< Position(line: 2, utf16index: 5),
      Position(line: 7, utf16index: 10) ..< Position(line: 8, utf16index: 10),
    ])
    checkCoding(call, json: """
      {
        "from" : {
          "kind" : 6,
          "name" : "test",
          "range" : {
            "end" : {
              "character" : 5,
              "line" : 2
            },
            "start" : {
              "character" : 0,
              "line" : 1
            }
          },
          "selectionRange" : {
            "end" : {
              "character" : 7,
              "line" : 1
            },
            "start" : {
              "character" : 0,
              "line" : 1
            }
          },
          "uri" : "file:\\/\\/\\/foo.swift"
        },
        "fromRanges" : [
          {
            "end" : {
              "character" : 5,
              "line" : 2
            },
            "start" : {
              "character" : 0,
              "line" : 2
            }
          },
          {
            "end" : {
              "character" : 10,
              "line" : 8
            },
            "start" : {
              "character" : 10,
              "line" : 7
            }
          }
        ]
      }
      """)
  }

  func testCustomCodableOptional() {
    struct WithPosRange: Codable, Equatable {
      @CustomCodable<PositionRange?>
      var range: Range<Position>?
    }

    let range = Position(line: 5, utf16index: 23) ..< Position(line: 6, utf16index: 0)
    checkCoding(WithPosRange(range: range), json: """
      {
        "range" : {
          "end" : {
            "character" : 0,
            "line" : 6
          },
          "start" : {
            "character" : 23,
            "line" : 5
          }
        }
      }
      """)

    checkCoding(WithPosRange(range: nil), json: """
      {

      }
      """)
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
