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

import LanguageServerProtocol
import SKCore
import SKSupport
import TSCBasic
import sourcekitd
import Dispatch
import struct Foundation.CharacterSet

public final class SwiftLanguageServer: LanguageServer {

  let sourcekitd: SwiftSourceKitFramework

  let buildSystem: BuildSystem

  let clientCapabilities: ClientCapabilities

  // FIXME: ideally we wouldn't need separate management from a parent server in the same process.
  var documentManager: DocumentManager

  var currentDiagnostics: [URL: [CachedDiagnostic]] = [:]

  var buildSettingsByFile: [URL: FileBuildSettings] = [:]

  let onExit: () -> Void

  var api: sourcekitd_functions_t { return sourcekitd.api }
  var keys: sourcekitd_keys { return sourcekitd.keys }
  var requests: sourcekitd_requests { return sourcekitd.requests }
  var values: sourcekitd_values { return sourcekitd.values }

  /// Creates a language server for the given client using the sourcekitd dylib at the specified path.
  public init(client: Connection, sourcekitd: AbsolutePath, buildSystem: BuildSystem, clientCapabilities: ClientCapabilities, onExit: @escaping () -> Void = {}) throws {

    self.sourcekitd = try SwiftSourceKitFramework(dylib: sourcekitd)
    self.buildSystem = buildSystem
    self.clientCapabilities = clientCapabilities
    self.documentManager = DocumentManager()
    self.onExit = onExit
    super.init(client: client)
  }

  public override func _registerBuiltinHandlers() {

    _register(SwiftLanguageServer.initialize)
    _register(SwiftLanguageServer.clientInitialized)
    _register(SwiftLanguageServer.cancelRequest)
    _register(SwiftLanguageServer.shutdown)
    _register(SwiftLanguageServer.exit)
    _register(SwiftLanguageServer.didChangeConfiguration)
    _register(SwiftLanguageServer.openDocument)
    _register(SwiftLanguageServer.closeDocument)
    _register(SwiftLanguageServer.changeDocument)
    _register(SwiftLanguageServer.willSaveDocument)
    _register(SwiftLanguageServer.didSaveDocument)
    _register(SwiftLanguageServer.completion)
    _register(SwiftLanguageServer.hover)
    _register(SwiftLanguageServer.documentSymbolHighlight)
    _register(SwiftLanguageServer.foldingRange)
    _register(SwiftLanguageServer.symbolInfo)
    _register(SwiftLanguageServer.documentSymbol)
    _register(SwiftLanguageServer.documentColor)
    _register(SwiftLanguageServer.colorPresentation)
    _register(SwiftLanguageServer.codeAction)
    _register(SwiftLanguageServer.executeCommand)
  }

  func publishDiagnostics(
    response: SKResponseDictionary,
    for snapshot: DocumentSnapshot)
  {
    let stageUID: sourcekitd_uid_t? = response[sourcekitd.keys.diagnostic_stage]
    let stage = stageUID.flatMap { DiagnosticStage($0, sourcekitd: sourcekitd) } ?? .sema

    // Note: we make the notification even if there are no diagnostics to clear the current state.
    var newDiags: [CachedDiagnostic] = []
    response[keys.diagnostics]?.forEach { _, diag in
      if let diag = CachedDiagnostic(diag, in: snapshot) {
        newDiags.append(diag)
      }
      return true
    }

    let document = snapshot.document.url

    let result = mergeDiagnostics(
      old: currentDiagnostics[document] ?? [],
      new: newDiags, stage: stage)
    currentDiagnostics[document] = result

    client.send(PublishDiagnostics(url: document, diagnostics: result.map { $0.diagnostic }))
  }

  func handleDocumentUpdate(url: URL) {
    guard let snapshot = documentManager.latestSnapshot(url) else {
      return
    }

    // Make the magic 0,0 replacetext request to update diagnostics.

    let req = SKRequestDictionary(sourcekitd: sourcekitd)
    req[keys.request] = requests.editor_replacetext
    req[keys.name] = url.path
    req[keys.offset] = 0
    req[keys.length] = 0
    req[keys.sourcetext] = ""

    if let dict = self.sourcekitd.sendSync(req).success {
      publishDiagnostics(response: dict, for: snapshot)
    }
  }
}

extension SwiftLanguageServer {

  func initialize(_ request: Request<InitializeRequest>) {

    api.initialize()

    api.set_notification_handler { [weak self] notification in
      guard let self = self else { return }
      let notification = SKResponse(notification, sourcekitd: self.sourcekitd)

      guard let dict = notification.value else {
        log(notification.description, level: .error)
        return
      }

      logAsync(level: .debug) { _ in notification.description }

      if let kind: sourcekitd_uid_t = dict[self.keys.notification],
        kind == self.values.notification_documentupdate,
        let name: String = dict[self.keys.name] {

        self.queue.async {
          self.handleDocumentUpdate(url: URL(fileURLWithPath: name))
        }
      }
    }

    request.reply(InitializeResult(capabilities: ServerCapabilities(
      textDocumentSync: TextDocumentSyncOptions(
        openClose: true,
        change: .incremental,
        willSave: true,
        willSaveWaitUntil: false,
        save: TextDocumentSyncOptions.SaveOptions(includeText: false)),
      completionProvider: CompletionOptions(
        resolveProvider: false,
        triggerCharacters: ["."]),
      hoverProvider: true,
      definitionProvider: nil,
      implementationProvider: true,
      referencesProvider: nil,
      documentHighlightProvider: true,
      foldingRangeProvider: true,
      documentSymbolProvider: true,
      colorProvider: true,
      codeActionProvider: CodeActionServerCapabilities(
        clientCapabilities: request.params.capabilities.textDocument?.codeAction,
        codeActionOptions: CodeActionOptions(codeActionKinds: nil),
        supportsCodeActions: true),
      executeCommandProvider: ExecuteCommandOptions(
        commands: builtinSwiftCommands)
    )))
  }

  func clientInitialized(_: Notification<InitializedNotification>) {
    // Nothing to do.
  }

  func cancelRequest(_ notification: Notification<CancelRequest>) {
    let key = RequestCancelKey(client: notification.clientID, request: notification.params.id)
    requestCancellation[key]?.cancel()
  }

  func shutdown(_ request: Request<Shutdown>) {
    api.set_notification_handler(nil)
  }

  func exit(_ notification: Notification<Exit>) {
    api.shutdown()
    onExit()
  }

  // MARK: - Workspace

  func didChangeConfiguration(notification: Notification<DidChangeConfiguration>) {
   switch notification.params.settings {
   case .clangd:
     break
   case .documentUpdated(let settings):
    documentBuildSettingsUpdated(settings.url, language: settings.language)
   case .unknown:
     break
   }
 }

  private func documentBuildSettingsUpdated(_ url: URL, language: Language) {
    guard let snapshot = documentManager.latestSnapshot(url) else {
      return
    }

    // Confirm that the build settings actually changed, otherwise we don't
    // need to do anything.
    let newSettings = buildSystem.settings(for: url, language)
    guard buildSettingsByFile[url] != newSettings else {
      return
    }
    buildSettingsByFile[url] = newSettings

    // Close and re-open the document internally to inform sourcekitd to
    // update the settings. At the moment there's no better way to do this.
    let closeReq = SKRequestDictionary(sourcekitd: sourcekitd)
    closeReq[keys.request] = requests.editor_close
    closeReq[keys.name] = url.path
    _ = self.sourcekitd.sendSync(closeReq)

    let openReq = SKRequestDictionary(sourcekitd: sourcekitd)
    openReq[keys.request] = requests.editor_open
    openReq[keys.name] = url.path
    openReq[keys.sourcetext] = snapshot.text
    if let settings = newSettings {
      openReq[keys.compilerargs] = settings.compilerArguments
    }

    guard let dict = self.sourcekitd.sendSync(openReq).success else {
      // Already logged failure.
      return
    }
    publishDiagnostics(response: dict, for: snapshot)
  }

  // MARK: - Text synchronization

  func openDocument(_ note: Notification<DidOpenTextDocument>) {
    guard let snapshot = documentManager.open(note) else {
      // Already logged failure.
      return
    }

    let req = SKRequestDictionary(sourcekitd: sourcekitd)
    req[keys.request] = requests.editor_open
    req[keys.name] = note.params.textDocument.url.path
    req[keys.sourcetext] = snapshot.text

    // If the BuildSystem has settings, cache them internally.
    let url = snapshot.document.url
    if let settings = buildSystem.settings(for: url, snapshot.document.language) {
      req[keys.compilerargs] = settings.compilerArguments
      buildSettingsByFile[url] = settings
    } else {
      buildSettingsByFile[url] = nil
    }

    guard let dict = self.sourcekitd.sendSync(req).success else {
      // Already logged failure.
      return
    }

    publishDiagnostics(response: dict, for: snapshot)
  }

  func closeDocument(_ note: Notification<DidCloseTextDocument>) {
    documentManager.close(note)

    let url = note.params.textDocument.url

    // Clear settings that should not be cached for closed documents.
    buildSettingsByFile[url] = nil
    currentDiagnostics[url] = nil

    let req = SKRequestDictionary(sourcekitd: sourcekitd)
    req[keys.request] = requests.editor_close
    req[keys.name] = url.path

    _ = self.sourcekitd.sendSync(req)
  }

  func changeDocument(_ note: Notification<DidChangeTextDocument>) {

    var lastResponse: SKResponseDictionary? = nil

    let snapshot = documentManager.edit(note) { (before: DocumentSnapshot, edit: TextDocumentContentChangeEvent) in
      let req = SKRequestDictionary(sourcekitd: self.sourcekitd)
      req[self.keys.request] = self.requests.editor_replacetext
      req[self.keys.name] = note.params.textDocument.url.path

      if let range = edit.range {

        guard let offset = before.utf8Offset(of: range.lowerBound), let end = before.utf8Offset(of: range.upperBound) else {
          fatalError("invalid edit \(range)")
        }

        req[self.keys.offset] = offset
        req[self.keys.length] = end - offset

      } else {
        // Full text
        req[self.keys.offset] = 0
        req[self.keys.length] = before.text.utf8.count
      }

      req[self.keys.sourcetext] = edit.text

      lastResponse = self.sourcekitd.sendSync(req).success
    }

    if let dict = lastResponse, let snapshot = snapshot {
      publishDiagnostics(response: dict, for: snapshot)
    }
  }

  func willSaveDocument(_ note: Notification<WillSaveTextDocument>) {

  }

  func didSaveDocument(_ note: Notification<DidSaveTextDocument>) {

  }

  // MARK: - Language features

  func completion(_ req: Request<CompletionRequest>) {

    guard let snapshot = documentManager.latestSnapshot(req.params.textDocument.url) else {
      log("failed to find snapshot for url \(req.params.textDocument.url)")
      req.reply(CompletionList(isIncomplete: true, items: []))
      return
    }

    guard let completionPos = adjustCompletionLocation(req.params.position, in: snapshot) else {
      log("invalid completion position \(req.params.position)")
      req.reply(CompletionList(isIncomplete: true, items: []))
      return
    }

    guard let offset = snapshot.utf8Offset(of: completionPos) else {
      log("invalid completion position \(req.params.position) (adjusted: \(completionPos)")
      req.reply(CompletionList(isIncomplete: true, items: []))
      return
    }

    let skreq = SKRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.codecomplete
    skreq[keys.offset] = offset
    skreq[keys.sourcefile] = snapshot.document.url.path
    skreq[keys.sourcetext] = snapshot.text

    // FIXME: SourceKit should probably cache this for us.
    if let settings = self.buildSettingsByFile[snapshot.document.url] {
      skreq[keys.compilerargs] = settings.compilerArguments
    }

    logAsync { _ in skreq.description }

    let handle = sourcekitd.send(skreq) { [weak self] result in
      guard let self = self else { return }
      guard let dict = result.success else {
        req.reply(.failure(result.failure!))
        return
      }

      guard let completions: SKResponseArray = dict[self.keys.results] else {
        req.reply(CompletionList(isIncomplete: false, items: []))
        return
      }

      var result = CompletionList(isIncomplete: false, items: [])

      let cancelled = !completions.forEach { (i, value) -> Bool in
        guard let name: String = value[self.keys.description] else {
          return true // continue
        }

        let filterName: String? = value[self.keys.name]
        let insertText: String? = value[self.keys.sourcetext]
        let typeName: String? = value[self.keys.typename]

        let clientCompletionCapabilities = self.clientCapabilities.textDocument?.completion
        let clientSupportsSnippets = clientCompletionCapabilities?.completionItem?.snippetSupport == true
        let text = insertText.map {
          self.rewriteSourceKitPlaceholders(inString: $0, clientSupportsSnippets: clientSupportsSnippets)
        }
        let isInsertTextSnippet = clientSupportsSnippets && text != insertText

        let kind: sourcekitd_uid_t? = value[self.keys.kind]
        result.items.append(CompletionItem(
          label: name,
          detail: typeName,
          sortText: nil,
          filterText: filterName,
          textEdit: nil,
          insertText: text,
          insertTextFormat: isInsertTextSnippet ? .snippet : .plain,
          kind: kind?.asCompletionItemKind(self.values) ?? .value,
          deprecated: nil
        ))

        return true
      }

      if !cancelled {
        req.reply(result)
      }
    }

    // FIXME: cancellation
    _ = handle
  }

  func rewriteSourceKitPlaceholders(inString string: String, clientSupportsSnippets: Bool) -> String {
    var result = string
    var index = 1
    while let start = result.range(of: EditorPlaceholder.placeholderPrefix) {
      guard let end = result[start.upperBound...].range(of: EditorPlaceholder.placeholderSuffix) else {
        log("invalid placeholder in \(string)", level: .debug)
        return string
      }
      let rawPlaceholder = String(result[start.lowerBound..<end.upperBound])
      guard let displayName = EditorPlaceholder(rawPlaceholder)?.displayName else {
        log("failed to decode placeholder \(rawPlaceholder) in \(string)", level: .debug)
        return string
      }
      let placeholder = clientSupportsSnippets ? "${\(index):\(displayName)}" : ""
      result.replaceSubrange(start.lowerBound..<end.upperBound, with: placeholder)
      index += 1
    }
    return result
  }

  /// Adjust completion position to the start of identifier characters.
  func adjustCompletionLocation(_ pos: Position, in snapshot: DocumentSnapshot) -> Position? {
    guard pos.line < snapshot.lineTable.count else {
      // Line out of range.
      return nil
    }
    let lineSlice = snapshot.lineTable[pos.line]
    let startIndex = lineSlice.startIndex

    let identifierChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    guard var loc = lineSlice.utf16.index(startIndex, offsetBy: pos.utf16index, limitedBy: lineSlice.endIndex) else {
      // Column out of range.
      return nil
    }
    while loc != startIndex {
      let prev = lineSlice.index(before: loc)
      if !identifierChars.contains(lineSlice.unicodeScalars[prev]) {
        break
      }
      loc = prev
    }

    // ###aabccccccdddddd
    // ^  ^- loc  ^-requestedLoc
    // `- startIndex

    let adjustedOffset = lineSlice.utf16.distance(from: startIndex, to: loc)
    return Position(line: pos.line, utf16index: adjustedOffset)
  }

  func hover(_ req: Request<HoverRequest>) {
    let url = req.params.textDocument.url
    let position = req.params.position
    cursorInfo(url, position) { result in
      guard let cursorInfo: CursorInfo = result.success ?? nil else {
        if let error = result.failure {
          log("cursor info failed \(url):\(position): \(error)", level: .warning)
        }
        return req.reply(nil)
      }

      guard let name: String = cursorInfo.symbolInfo.name else {
        // There is a cursor but we don't know how to deal with it.
        req.reply(nil)
        return
      }

      /// Prepend backslash to `*` and `_`, to prevent them
      /// from being interpreted as markdown.
      func escapeNameMarkdown(_ str: String) -> String {
        return String(str.flatMap({ ($0 == "*" || $0 == "_") ? ["\\", $0] : [$0] }))
      }

      var result = "# \(escapeNameMarkdown(name))"
      if let doc = cursorInfo.documentationXML {
        result += """

        \(orLog { try xmlDocumentationToMarkdown(doc) } ?? doc)
        """
      } else if let annotated: String = cursorInfo.annotatedDeclaration {
        result += """

        \(orLog { try xmlDocumentationToMarkdown(annotated) } ?? annotated)
        """
      }

      req.reply(HoverResponse(contents: MarkupContent(kind: .markdown, value: result), range: nil))
    }
  }

  func symbolInfo(_ req: Request<SymbolInfoRequest>) {
    let url = req.params.textDocument.url
    let position = req.params.position
    cursorInfo(url, position) { result in
      guard let cursorInfo: CursorInfo = result.success ?? nil else {
        if let error = result.failure {
          log("cursor info failed \(url):\(position): \(error)", level: .warning)
        }
        return req.reply([])
      }

      req.reply([cursorInfo.symbolInfo])
    }
  }

  func documentSymbol(_ req: Request<DocumentSymbolRequest>) {
    guard let snapshot = documentManager.latestSnapshot(req.params.textDocument.url) else {
      log("failed to find snapshot for url \(req.params.textDocument.url)")
      req.reply(nil)
      return
    }

    let skreq = SKRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.editor_open
    skreq[keys.name] = "DocumentSymbols:" + snapshot.document.url.path
    skreq[keys.sourcetext] = snapshot.text
    skreq[keys.syntactic_only] = 1

    let handle = sourcekitd.send(skreq) { [weak self] result in
      guard let self = self else { return }
      guard let dict = result.success else {
        req.reply(.failure(result.failure!))
        return
      }
      guard let results: SKResponseArray = dict[self.keys.substructure] else {
        return req.reply([])
      }

      func documentSymbol(value: SKResponseDictionary) -> DocumentSymbol? {
        guard let name: String = value[self.keys.name],
              let uid: sourcekitd_uid_t = value[self.keys.kind],
              let kind: SymbolKind = uid.asSymbolKind(self.values),
              let offset: Int = value[self.keys.offset],
              let start: Position = snapshot.positionOf(utf8Offset: offset),
              let length: Int = value[self.keys.length],
              let end: Position = snapshot.positionOf(utf8Offset: offset + length) else {
          return nil
        }
        
        let range = start..<end
        let selectionRange: Range<Position>
        if let nameOffset: Int = value[self.keys.nameoffset],
           let nameStart: Position = snapshot.positionOf(utf8Offset: nameOffset),
           let nameLength: Int = value[self.keys.namelength],
           let nameEnd: Position = snapshot.positionOf(utf8Offset: nameOffset + nameLength) {
          selectionRange = nameStart..<nameEnd
        } else {
          selectionRange = range
        }

        let children: [DocumentSymbol]?
        if let substructure: SKResponseArray = value[self.keys.substructure] {
          children = documentSymbols(array: substructure)
        } else {
          children = nil
        }
        return DocumentSymbol(name: name,
                              detail: nil,
                              kind: kind,
                              deprecated: nil,
                              range: range,
                              selectionRange: selectionRange,
                              children: children)
      }

      func documentSymbols(array: SKResponseArray) -> [DocumentSymbol] {
        var result: [DocumentSymbol] = []
        array.forEach { (i: Int, value: SKResponseDictionary) in
          if let documentSymbol = documentSymbol(value: value) {
            result.append(documentSymbol)
          } else if let substructure: SKResponseArray = value[self.keys.substructure] {
            result += documentSymbols(array: substructure)
          }
          return true
        }
        return result
      }
      
      req.reply(documentSymbols(array: results))
    }
    // FIXME: cancellation
    _ = handle
    return
  }

  func documentColor(_ req: Request<DocumentColorRequest>) {
    guard let snapshot = documentManager.latestSnapshot(req.params.textDocument.url) else {
      log("failed to find snapshot for url \(req.params.textDocument.url)")
      req.reply(nil)
      return
    }

    let skreq = SKRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.editor_open
    skreq[keys.name] = "DocumentColor:" + snapshot.document.url.path
    skreq[keys.sourcetext] = snapshot.text
    skreq[keys.syntactic_only] = 1

    let handle = sourcekitd.send(skreq) { [weak self] result in      
      guard let self = self else { return }
      guard let dict = result.success else {
        req.reply(.failure(result.failure!))
        return
      }
      
      guard let results: SKResponseArray = dict[self.keys.substructure] else {
        return req.reply([])
      }
      
      func colorInformation(dict: SKResponseDictionary) -> ColorInformation? {
        guard let kind: sourcekitd_uid_t = dict[self.keys.kind],
              kind == self.values.expr_object_literal,
              let name: String = dict[self.keys.name],
              name == "colorLiteral",
              let offset: Int = dict[self.keys.offset],
              let start: Position = snapshot.positionOf(utf8Offset: offset),
              let length: Int = dict[self.keys.length],
              let end: Position = snapshot.positionOf(utf8Offset: offset + length),
              let substructure: SKResponseArray = dict[self.keys.substructure] else {
          return nil
        }
        var red, green, blue, alpha: Double?
        substructure.forEach{ (i: Int, value: SKResponseDictionary) in
          guard let name: String = value[self.keys.name],
                let bodyoffset: Int = value[self.keys.bodyoffset],
                let bodylength: Int = value[self.keys.bodylength] else {
            return true
          }
          let view = snapshot.text.utf8
          let bodyStart = view.index(view.startIndex, offsetBy: bodyoffset)
          let bodyEnd = view.index(view.startIndex, offsetBy: bodyoffset+bodylength)
          let value = String(view[bodyStart..<bodyEnd]).flatMap(Double.init)
          switch name {
            case "red":
              red = value
            case "green":
              green = value
            case "blue":
              blue = value
            case "alpha":
              alpha = value
            default:
              break
          }
          return true
        }
        if let red = red,
           let green = green,
           let blue = blue,
           let alpha = alpha {
          let color = Color(red: red, green: green, blue: blue, alpha: alpha)
          return ColorInformation(range: start..<end, color: color)
        } else {
          return nil
        }
      }
      
      func colorInformation(array: SKResponseArray) -> [ColorInformation] {
        var result: [ColorInformation] = []
        array.forEach { (i: Int, value: SKResponseDictionary) in
          if let documentSymbol = colorInformation(dict: value) {
            result.append(documentSymbol)
          } else if let substructure: SKResponseArray = value[self.keys.substructure] {
            result += colorInformation(array: substructure)
          }
          return true
        }
        return result
      }

      req.reply(colorInformation(array: results))
    }
    // FIXME: cancellation
    _ = handle
  }

  func colorPresentation(_ req: Request<ColorPresentationRequest>) {
    let color = req.params.color
    // Empty string as a label breaks VSCode color picker
    let label = "Color Literal"
    let newText = "#colorLiteral(red: \(color.red), green: \(color.green), blue: \(color.blue), alpha: \(color.alpha))"
    let textEdit = TextEdit(range: req.params.range, newText: newText)
    let presentation = ColorPresentation(label: label, textEdit: textEdit, additionalTextEdits: nil)
    req.reply([presentation])
  }

  func documentSymbolHighlight(_ req: Request<DocumentHighlightRequest>) {

    guard let snapshot = documentManager.latestSnapshot(req.params.textDocument.url) else {
      log("failed to find snapshot for url \(req.params.textDocument.url)")
      req.reply(nil)
      return
    }

    guard let offset = snapshot.utf8Offset(of: req.params.position) else {
      log("invalid position \(req.params.position)")
      req.reply(nil)
      return
    }

    let skreq = SKRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.relatedidents
    skreq[keys.offset] = offset
    skreq[keys.sourcefile] = snapshot.document.url.path

    // FIXME: SourceKit should probably cache this for us.
    if let settings = self.buildSettingsByFile[snapshot.document.url] {
      skreq[keys.compilerargs] = settings.compilerArguments
    }

    let handle = sourcekitd.send(skreq) { [weak self] result in
      guard let self = self else { return }
      guard let dict = result.success else {
        req.reply(.failure(result.failure!))
        return
      }

      guard let results: SKResponseArray = dict[self.keys.results] else {
        return req.reply([])
      }

      var highlights: [DocumentHighlight] = []

      results.forEach { _, value in
        if let offset: Int = value[self.keys.offset],
           let start: Position = snapshot.positionOf(utf8Offset: offset),
           let length: Int = value[self.keys.length],
           let end: Position = snapshot.positionOf(utf8Offset: offset + length)
        {
          highlights.append(DocumentHighlight(
            range: start..<end,
            kind: .read // unknown
          ))
        }
        return true
      }

      req.reply(highlights)
    }

    // FIXME: cancellation
    _ = handle
  }

  func foldingRange(_ req: Request<FoldingRangeRequest>) {
    guard let snapshot = documentManager.latestSnapshot(req.params.textDocument.url) else {
      log("failed to find snapshot for url \(req.params.textDocument.url)")
      req.reply(nil)
      return
    }

    let skreq = SKRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.editor_open
    skreq[keys.name] = "FoldingRanges:" + snapshot.document.url.path
    skreq[keys.sourcetext] = snapshot.text
    skreq[keys.syntactic_only] = 1

    let handle = sourcekitd.send(skreq) { [weak self] result in
      guard let self = self else { return }
      guard let dict = result.success else {
        req.reply(.failure(result.failure!))
        return
      }

      guard let syntaxMap: SKResponseArray = dict[self.keys.syntaxmap],
            let substructure: SKResponseArray = dict[self.keys.substructure] else {
        return req.reply([])
      }

      var ranges: [FoldingRange] = []

      var hasReachedLimit: Bool {
        let capabilities = self.clientCapabilities.textDocument?.foldingRange
        guard let rangeLimit = capabilities?.rangeLimit else {
          return false
        }
        return ranges.count >= rangeLimit
      }

      // If the limit is less than one, do nothing.
      guard hasReachedLimit == false else {
        req.reply([])
        return
      }

      // Merge successive comments into one big comment by adding their lengths.
      var currentComment: (offset: Int, length: Int)? = nil

      syntaxMap.forEach { _, value in
        if let kind: sourcekitd_uid_t = value[self.keys.kind],
           kind.isCommentKind(self.values),
           let offset: Int = value[self.keys.offset],
           let length: Int = value[self.keys.length]
        {
          if let comment = currentComment, comment.offset + comment.length == offset {
            currentComment!.length += length
            return true
          }
          if let comment = currentComment {
            self.addFoldingRange(offset: comment.offset, length: comment.length, kind: .comment, in: snapshot, toArray: &ranges)
          }
          currentComment = (offset: offset, length: length)
        }
        return hasReachedLimit == false
      }

      // Add the last stored comment.
      if let comment = currentComment, hasReachedLimit == false {
        self.addFoldingRange(offset: comment.offset, length: comment.length, kind: .comment, in: snapshot, toArray: &ranges)
        currentComment = nil
      }

      var structureStack: [SKResponseArray] = [substructure]
      while !hasReachedLimit, let substructure = structureStack.popLast() {
        substructure.forEach { _, value in
          if let offset: Int = value[self.keys.bodyoffset],
             let length: Int = value[self.keys.bodylength],
             length > 0
          {
            self.addFoldingRange(offset: offset, length: length, in: snapshot, toArray: &ranges)
            if hasReachedLimit {
              return false
            }
          }
          if let substructure: SKResponseArray = value[self.keys.substructure] {
            structureStack.append(substructure)
          }
          return true
        }
      }

      ranges.sort()
      req.reply(ranges)
    }

    // FIXME: cancellation
    _ = handle
  }

  func addFoldingRange(offset: Int, length: Int, kind: FoldingRangeKind? = nil, in snapshot: DocumentSnapshot, toArray ranges: inout [FoldingRange]) {
    guard let start: Position = snapshot.positionOf(utf8Offset: offset),
          let end: Position = snapshot.positionOf(utf8Offset: offset + length) else {
      log("folding range failed to retrieve position of \(snapshot.document.url): \(offset)-\(offset + length)", level: .warning)
      return
    }
    let capabilities = clientCapabilities.textDocument?.foldingRange
    let range: FoldingRange
    // If the client only supports folding full lines, ignore the end character's line.
    if capabilities?.lineFoldingOnly == true {
      let lastLineToFold = end.line - 1
      if lastLineToFold <= start.line {
        return
      } else {
        range = FoldingRange(startLine: start.line,
                             startUTF16Index: nil,
                             endLine: lastLineToFold,
                             endUTF16Index: nil,
                             kind: kind)
      }
    } else {
      range = FoldingRange(startLine: start.line,
                           startUTF16Index: start.utf16index,
                           endLine: end.line,
                           endUTF16Index: end.utf16index,
                           kind: kind)
    }
    ranges.append(range)
  }

  func codeAction(_ req: Request<CodeActionRequest>) {
    let providersAndKinds: [(provider: CodeActionProvider, kind: CodeActionKind)] = [
      (retrieveRefactorCodeActions, .refactor)
      //TODO: Implement the providers.
      //(retrieveQuickFixCodeActions, .quickFix)
    ]
    let wantedActionKinds = req.params.context.only
    let providers = providersAndKinds.filter { wantedActionKinds?.contains($0.1) != false }
    retrieveCodeActions(req, providers: providers.map { $0.provider }) { result in
      switch result {
      case .success(let codeActions):
        let capabilities = self.clientCapabilities.textDocument?.codeAction
        let response = CodeActionRequestResponse(codeActions: codeActions,
                                                 clientCapabilities: capabilities)
        req.reply(response)
      case .failure(let error):
        req.reply(.failure(error))
      }
    }
  }

  func retrieveCodeActions(_ req: Request<CodeActionRequest>, providers: [CodeActionProvider], completion: @escaping CodeActionProviderCompletion) {
    guard providers.isEmpty == false else {
      completion(.success([]))
      return
    }
    var codeActions = [CodeAction]()
    let dispatchGroup = DispatchGroup()
    (0..<providers.count).forEach { _ in dispatchGroup.enter() }
    dispatchGroup.notify(queue: queue) {
      completion(.success(codeActions))
    }
    for i in 0..<providers.count {
      providers[i](req.params) { result in
        defer { dispatchGroup.leave() }
        guard case .success(let actions) = result else {
          return
        }
        self.queue.sync {
          codeActions += actions
        }
      }
    }
  }

  func retrieveRefactorCodeActions(_ params: CodeActionRequest, completion: @escaping CodeActionProviderCompletion) {
    guard let snapshot = documentManager.latestSnapshot(params.textDocument.url) else {
      let message = "failed to find snapshot for url \(params.textDocument.url)"
      log(message)
      completion(.failure(.unknown(message)))
      return
    }

    guard let offsetRange = snapshot.utf8OffsetRange(of: params.range) else {
      let message = "failed to retrieve range from \(params.range)"
      log(message)
      completion(.failure(.unknown(message)))
      return
    }

    let additionalCursorInfoParameters: ((SKRequestDictionary) -> Void) = { skreq in
      skreq[self.keys.length] = offsetRange.count
      skreq[self.keys.retrieve_refactor_actions] = 1
    }

    cursorInfo(
      params.textDocument.url,
      params.range.lowerBound,
      customCursorOffset: offsetRange.lowerBound,
      additionalParameters: additionalCursorInfoParameters)
    { result in
      guard let dict: CursorInfo = result.success ?? nil else {
        if let failure = result.failure {
          let message = "failed to find refactor actions: \(failure)"
          log(message)
          completion(.failure(.unknown(message)))
        } else {
          completion(.failure(.unknown("CursorInfo failed.")))
        }
        return
      }
      guard let results: SKResponseArray = dict.refactorActions else {
        completion(.success([]))
        return
      }
      var codeActions = [CodeAction]()
      results.forEach { _, value in
        if let name: String = value[self.keys.actionname],
           let actionuid: sourcekitd_uid_t = value[self.keys.actionuid],
           let ptr = self.sourcekitd.api.uid_get_string_ptr(actionuid)
        {
          let actionName = String(cString: ptr)
          guard actionName != "source.refactoring.kind.rename.global" else {
            // TODO: Global refactoring
            return true
          }
          let refactorCommand = SemanticRefactorCommand(
            title: name,
            actionString: actionName,
            positionRange: params.range,
            textDocument: params.textDocument)
          do {
            let lspCommand = try refactorCommand.asCommand()
            let codeAction = CodeAction(title: name, kind: .refactor, command: lspCommand)
            codeActions.append(codeAction)
          } catch {
            log("Failed to convert SwiftCommand to Command type: \(error)", level: .error)
          }
        }
        return true
      }

      completion(.success(codeActions))
    }
  }

  func executeCommand(_ req: Request<ExecuteCommandRequest>) {
    let params = req.params
    //TODO: If there's support for several types of commands, we might need to structure this similarly to the code actions request.
    guard let swiftCommand = params.swiftCommand(ofType: SemanticRefactorCommand.self) else {
      let message = "semantic refactoring: unknown command \(params.command)"
      log(message, level: .warning)
      return req.reply(.failure(.unknown(message)))
    }
    let url = swiftCommand.textDocument.url
    semanticRefactoring(swiftCommand) { result in
      switch result {
      case .success(let refactor):
        let edit = refactor.edit
        self.applyEdit(label: refactor.title, edit: edit) { editResult in
          switch editResult {
          case .success:
            req.reply(edit.encodeToLSPAny())
          case .failure(let error):
            req.reply(.failure(error))
          }
        }
      case .failure(let error):
        let message = "semantic refactoring failed \(url): \(error)"
        log(message, level: .warning)
        return req.reply(.failure(.unknown(message)))
      }
    }
  }

  func applyEdit(label: String, edit: WorkspaceEdit, completion: @escaping (Result<ApplyEditResponse, ResponseError>) -> Void) {
    let req = ApplyEditRequest(label: label, edit: edit)
    let handle = client.send(req, queue: queue) { reply in
      switch reply {
      case .success(let response) where response.applied == false:
        let reason: String
        if let failureReason = response.failureReason {
          reason = " reason: \(failureReason)"
        } else {
          reason = ""
        }
        log("client refused to apply edit for \(label)!\(reason)", level: .warning)
      case .failure(let error):
        log("applyEdit failed: \(error)", level: .warning)
      default:
        break
      }
      completion(reply)
    }

    // FIXME: cancellation
    _ = handle
  }
}

extension DocumentSnapshot {

  func utf8Offset(of pos: Position) -> Int? {
    return lineTable.utf8OffsetOf(line: pos.line, utf16Column: pos.utf16index)
  }

  func utf8OffsetRange(of range: Range<Position>) -> Range<Int>? {
    guard let startOffset = utf8Offset(of: range.lowerBound),
          let endOffset = utf8Offset(of: range.upperBound) else
    {
      return nil
    }
    return startOffset..<endOffset
  }

  func positionOf(utf8Offset: Int) -> Position? {
    return lineTable.lineAndUTF16ColumnOf(utf8Offset: utf8Offset).map {
      Position(line: $0.line, utf16index: $0.utf16Column)
    }
  }

  func positionOf(zeroBasedLine: Int, utf8Column: Int) -> Position? {
    return lineTable.utf16ColumnAt(line: zeroBasedLine, utf8Column: utf8Column).map {
      Position(line: zeroBasedLine, utf16index: $0)
    }
  }
}

func makeLocalSwiftServer(client: MessageHandler, sourcekitd: AbsolutePath, buildSettings: BuildSystem?, clientCapabilities: ClientCapabilities?) throws -> Connection {

  let connectionToSK = LocalConnection()
  let connectionToClient = LocalConnection()

  let server = try SwiftLanguageServer(
    client: connectionToClient,
    sourcekitd: sourcekitd,
    buildSystem: buildSettings ?? BuildSystemList(),
    clientCapabilities: clientCapabilities ?? ClientCapabilities(workspace: nil, textDocument: nil)
  )

  connectionToSK.start(handler: server)
  connectionToClient.start(handler: client)

  return connectionToSK
}

extension sourcekitd_uid_t {
  func isCommentKind(_ vals: sourcekitd_values) -> Bool {
    switch self {
      case vals.syntaxtype_comment, vals.syntaxtype_comment_marker, vals.syntaxtype_comment_url:
        return true
      default:
        return isDocCommentKind(vals)
    }
  }

  func isDocCommentKind(_ vals: sourcekitd_values) -> Bool {
    return self == vals.syntaxtype_doccomment || self == vals.syntaxtype_doccomment_field
  }

  func asCompletionItemKind(_ vals: sourcekitd_values) -> CompletionItemKind? {
    switch self {
      case vals.kind_keyword:
        return .keyword
      case vals.decl_module:
        return .module
      case vals.decl_class:
        return .class
      case vals.decl_struct:
        return .struct
      case vals.decl_enum:
        return .enum
      case vals.decl_enumelement:
        return .enumMember
      case vals.decl_protocol:
        return .interface
      case vals.decl_associatedtype:
        return .typeParameter
      case vals.decl_typealias:
        return .typeParameter // FIXME: is there a better choice?
      case vals.decl_generic_type_param:
        return .typeParameter
      case vals.decl_function_constructor:
        return .constructor
      case vals.decl_function_destructor:
        return .value // FIXME: is there a better choice?
      case vals.decl_function_subscript:
        return .method // FIXME: is there a better choice?
      case vals.decl_function_method_static:
        return .method
      case vals.decl_function_method_instance:
        return .method
      case vals.decl_function_operator_prefix,
           vals.decl_function_operator_postfix,
           vals.decl_function_operator_infix:
        return .operator
      case vals.decl_precedencegroup:
        return .value
      case vals.decl_function_free:
        return .function
      case vals.decl_var_static, vals.decl_var_class:
        return .property
      case vals.decl_var_instance:
        return .property
      case vals.decl_var_local,
           vals.decl_var_global,
           vals.decl_var_parameter:
        return .variable
      default:
        return nil
    }
  }

  func asSymbolKind(_ vals: sourcekitd_values) -> SymbolKind? {
    switch self {
      case vals.decl_class:
        return .class
      case vals.decl_function_method_instance,
           vals.decl_function_method_static, 
           vals.decl_function_method_class:
        return .method
      case vals.decl_var_instance, 
           vals.decl_var_static,
           vals.decl_var_class:
        return .property
      case vals.decl_enum:
        return .enum
      case vals.decl_enumelement:
        return .enumMember
      case vals.decl_protocol:
        return .interface
      case vals.decl_function_free:
        return .function
      case vals.decl_var_global, 
           vals.decl_var_local:
        return .variable
      case vals.decl_struct:
        return .struct
      case vals.decl_generic_type_param:
        return .typeParameter
      case vals.decl_extension:
        // There are no extensions in LSP, so I return something vaguely similar
        return .namespace
      default:
        return nil
    }
  }
}
