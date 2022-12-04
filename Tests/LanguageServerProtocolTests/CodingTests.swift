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

    checkCoding(OptionalVersionedTextDocumentIdentifier(uri, version: nil), json: """
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

    checkCoding(
      TextDocumentEdit(
        textDocument: OptionalVersionedTextDocumentIdentifier(uri, version: 1),
        edits: [
          .textEdit(TextEdit(range: range, newText: "foo"))
        ]
      ), json: """
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

    checkCoding(StringOrMarkupContent.markupContent(MarkupContent(kind: .markdown, value: "some **Markdown***")), json: """
      {
        "kind" : "markdown",
        "value" : "some **Markdown***"
      }
      """)

    checkCoding(StringOrMarkupContent.string("Some documentation"), json: """
      "Some documentation"
      """)
    
    checkCoding(PrepareRenameResponse(range: range), json: rangejson)
    
    checkCoding(PrepareRenameResponse(range: range, placeholder: "somePlaceholder"), json: """
      {
        "placeholder" : "somePlaceholder",
        "range" : \(rangejson.indented(2, skipFirstLine: true))
      }
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
    
    checkCoding(WorkspaceEdit(documentChanges: [.textDocumentEdit(TextDocumentEdit(textDocument: OptionalVersionedTextDocumentIdentifier(uri, version: 2), edits: []))]), json: """
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

  func testCompletionListItemDefaultsEditRange() {
    checkCoding(CompletionList.ItemDefaultsEditRange.range(Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3)), json: """
    {
      "end" : {
        "character" : 3,
        "line" : 4
      },
      "start" : {
        "character" : 14,
        "line" : 3
      }
    }
    """)

    checkCoding(CompletionList.ItemDefaultsEditRange.insertReplaceRanges(.init(
      insert: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3),
      replace: Position(line: 5, utf16index: 12)..<Position(line: 6, utf16index: 2)
    )), json: """
    {
      "insert" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      },
      "replace" : {
        "end" : {
          "character" : 2,
          "line" : 6
        },
        "start" : {
          "character" : 12,
          "line" : 5
        }
      }
    }
    """)
  }

  func testProgressToken() {
    checkCoding(ProgressToken.integer(3), json: "3")
    checkCoding(ProgressToken.string("foobar"), json: #""foobar""#)
  }

  func testDocumentDiagnosticReport() {
    checkCoding(DocumentDiagnosticReport.full(RelatedFullDocumentDiagnosticReport(items: [])), json: """
    {
      "items" : [

      ],
      "kind" : "full"
    }
    """)

    checkCoding(DocumentDiagnosticReport.full(RelatedFullDocumentDiagnosticReport(resultId: "myResults", items: [])), json: """
    {
      "items" : [

      ],
      "kind" : "full",
      "resultId" : "myResults"
    }
    """)

    checkCoding(DocumentDiagnosticReport.full(RelatedFullDocumentDiagnosticReport(
      resultId: "myResults",
      items: [],
      relatedDocuments: [
        DocumentURI(string: "file:///some/path"): DocumentDiagnosticReport.unchanged(RelatedUnchangedDocumentDiagnosticReport(resultId: "myOtherResults"))
      ]
    )), json: #"""
    {
      "items" : [

      ],
      "kind" : "full",
      "relatedDocuments" : [
        "file:\/\/\/some\/path",
        {
          "kind" : "unchanged",
          "resultId" : "myOtherResults"
        }
      ],
      "resultId" : "myResults"
    }
    """#)

    checkCoding(DocumentDiagnosticReport.unchanged(RelatedUnchangedDocumentDiagnosticReport(resultId: "myResults")), json: """
    {
      "kind" : "unchanged",
      "resultId" : "myResults"
    }
    """)

    checkCoding(DocumentDiagnosticReport.unchanged(RelatedUnchangedDocumentDiagnosticReport(resultId: "myResults", relatedDocuments: [
      DocumentURI(string: "file:///some/path"): DocumentDiagnosticReport.unchanged(RelatedUnchangedDocumentDiagnosticReport(resultId: "myOtherResults"))
    ])), json: #"""
    {
      "kind" : "unchanged",
      "relatedDocuments" : [
        "file:\/\/\/some\/path",
        {
          "kind" : "unchanged",
          "resultId" : "myOtherResults"
        }
      ],
      "resultId" : "myResults"
    }
    """#)
  }

  func testInlineValue() {
    checkCoding(InlineValue.text(InlineValueText(
      range: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3),
      text: "xxx"
    )), json: """
    {
      "range" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      },
      "text" : "xxx"
    }
    """)

    checkCoding(InlineValue.variableLookup(InlineValueVariableLookup(
      range: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3),
      variableName: "myVar",
      caseSensitiveLookup: true
    )), json: """
    {
      "caseSensitiveLookup" : true,
      "range" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      },
      "variableName" : "myVar"
    }
    """)

    checkCoding(InlineValue.evaluatableExpression(InlineValueEvaluatableExpression(
      range: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3),
      expression: "myExpr"
    )), json: """
    {
      "expression" : "myExpr",
      "range" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      }
    }
    """)
  }

  func testSelectionRange() {
    checkCoding(SelectionRange(
      range: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3),
      parent: SelectionRange(range: Position(line: 1, utf16index: 13)..<Position(line: 5, utf16index: 13))
    ), json: """
    {
      "parent" : {
        "range" : {
          "end" : {
            "character" : 13,
            "line" : 5
          },
          "start" : {
            "character" : 13,
            "line" : 1
          }
        }
      },
      "range" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      }
    }
    """)
  }

  func testParameterInformationLabel() {
    checkCoding(ParameterInformation.Label.string("hello"), json: #""hello""#)
    checkCoding(ParameterInformation.Label.offsets(start: 4, end: 8), json: """
    [
      4,
      8
    ]
    """)
  }

  func testWorkspaceDocumentDiagnosticReport() {
    checkCoding(WorkspaceDocumentDiagnosticReport.full(WorkspaceFullDocumentDiagnosticReport(items: [], uri: DocumentURI(string: "file:///some/path"))), json: #"""
    {
      "items" : [

      ],
      "kind" : "full",
      "uri" : "file:\/\/\/some\/path"
    }
    """#)

    checkCoding(WorkspaceDocumentDiagnosticReport.unchanged(WorkspaceUnchangedDocumentDiagnosticReport(resultId: "myResults", uri: DocumentURI(string: "file:///some/path"))), json: #"""
    {
      "kind" : "unchanged",
      "resultId" : "myResults",
      "uri" : "file:\/\/\/some\/path"
    }
    """#)
  }

  func testWorkspaceSymbolItem() {
    checkCoding(WorkspaceSymbolItem.symbolInformation(SymbolInformation(
      name: "mySym",
      kind: .constant,
      location: Location(
        uri: DocumentURI(string: "file:///some/path"),
        range: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3)
      )
    )), json: #"""
    {
      "kind" : 14,
      "location" : {
        "range" : {
          "end" : {
            "character" : 3,
            "line" : 4
          },
          "start" : {
            "character" : 14,
            "line" : 3
          }
        },
        "uri" : "file:\/\/\/some\/path"
      },
      "name" : "mySym"
    }
    """#)

    checkCoding(WorkspaceSymbolItem.workspaceSymbol(WorkspaceSymbol(
      name: "mySym",
      kind: .boolean,
      location: WorkspaceSymbol.WorkspaceSymbolLocation.uri(.init(uri: DocumentURI(string: "file:///some/path")))
    )), json: #"""
    {
      "kind" : 17,
      "location" : {
        "uri" : "file:\/\/\/some\/path"
      },
      "name" : "mySym"
    }
    """#)
  }

  func testWorkspapceSymbolLocation() {
    checkCoding(WorkspaceSymbol.WorkspaceSymbolLocation.uri(.init(uri: DocumentURI(string: "file:///some/path"))), json: #"""
    {
      "uri" : "file:\/\/\/some\/path"
    }
    """#)

    checkCoding(WorkspaceSymbol.WorkspaceSymbolLocation.location(Location(
      uri: DocumentURI(string: "file:///some/path"),
      range: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3)
    )), json: #"""
    {
      "range" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      },
      "uri" : "file:\/\/\/some\/path"
    }
    """#)
  }

  func testCompletionItemEdit() {
    checkCoding(CompletionItemEdit.textEdit(TextEdit(
      range: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3),
      newText: "some new text"
    )), json: """
    {
      "newText" : "some new text",
      "range" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      }
    }
    """)

    checkCoding(CompletionItemEdit.insertReplaceEdit(InsertReplaceEdit(
      newText: "some new text",
      insert: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3),
      replace: Position(line: 2, utf16index: 8)..<Position(line: 2, utf16index: 9)
    )), json: """
    {
      "insert" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      },
      "newText" : "some new text",
      "replace" : {
        "end" : {
          "character" : 9,
          "line" : 2
        },
        "start" : {
          "character" : 8,
          "line" : 2
        }
      }
    }
    """)
  }

  func testNotebookCellTextDocumentFilter() {
    checkCoding(NotebookCellTextDocumentFilter.NotebookFilter.string("abc"), json: #""abc""#)
    checkCoding(NotebookCellTextDocumentFilter.NotebookFilter.notebookDocumentFilter(NotebookDocumentFilter(pattern: "xxx")), json: """
    {
      "pattern" : "xxx"
    }
    """)
  }

  func testStringOrMarkupContent() {
    checkCoding(StringOrMarkupContent.string("hello"), json: #""hello""#)
    checkCoding(StringOrMarkupContent.markupContent(MarkupContent(kind: .markdown, value: "hello")), json: """
    {
      "kind" : "markdown",
      "value" : "hello"
    }
    """)
  }

  func testTextDocumentEdit() {
    checkCoding(TextDocumentEdit.Edit.textEdit(TextEdit(
      range: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3),
      newText: "some new text"
    )), json: """
    {
      "newText" : "some new text",
      "range" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      }
    }
    """)

    checkCoding(TextDocumentEdit.Edit.annotatedTextEdit(AnnotatedTextEdit(
      range: Position(line: 3, utf16index: 14)..<Position(line: 4, utf16index: 3),
      newText: "some new text",
      annotationId: "change-34"
    )), json: """
    {
      "annotationId" : "change-34",
      "newText" : "some new text",
      "range" : {
        "end" : {
          "character" : 3,
          "line" : 4
        },
        "start" : {
          "character" : 14,
          "line" : 3
        }
      }
    }
    """)
  }

  func testWorkDoneProgress() {
    checkCoding(WorkDoneProgress.begin(WorkDoneProgressBegin(title: "My Work")), json: """
    {
      "kind" : "begin",
      "title" : "My Work"
    }
    """)

    checkCoding(WorkDoneProgress.report(WorkDoneProgressReport(message: "Still working")), json: """
    {
      "kind" : "report",
      "message" : "Still working"
    }
    """)

    checkCoding(WorkDoneProgress.end(WorkDoneProgressEnd()), json: """
    {
      "kind" : "end"
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
