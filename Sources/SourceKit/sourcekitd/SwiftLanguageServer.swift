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
import SKCore
import SKSupport
import Basic
import sourcekitd
import struct Foundation.CharacterSet

public final class SwiftLanguageServer: LanguageServer {

  let sourcekitd: SwiftSourceKitFramework

  let buildSettingsProvider: BuildSettingsProvider

  // FIXME: ideally we wouldn't need separate management from a parent server in the same process.
  var documentManager: DocumentManager

  let onExit: () -> ()

  var api: sourcekitd_functions_t { return sourcekitd.api }
  var keys: sourcekitd_keys { return sourcekitd.keys }
  var requests: sourcekitd_requests { return sourcekitd.requests }
  var values: sourcekitd_values { return sourcekitd.values }

  /// Creates a language server for the given client using the sourcekitd dylib at the specified path.
  public init(client: Connection, sourcekitd: AbsolutePath, buildSettingsProvider: BuildSettingsProvider, onExit: @escaping () -> () = {}) throws {

    self.sourcekitd = try SwiftSourceKitFramework(dylib: sourcekitd)
    self.buildSettingsProvider = buildSettingsProvider
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
    _register(SwiftLanguageServer.openDocument)
    _register(SwiftLanguageServer.closeDocument)
    _register(SwiftLanguageServer.changeDocument)
    _register(SwiftLanguageServer.willSaveDocument)
    _register(SwiftLanguageServer.didSaveDocument)
    _register(SwiftLanguageServer.completion)
    _register(SwiftLanguageServer.hover)
    _register(SwiftLanguageServer.documentSymbolHighlight)
  }

  func getDiagnostic(_ diag: SKResponseDictionary, for snapshot: DocumentSnapshot) -> Diagnostic? {

    // FIXME: this assumes that the diagnostics are all in the same file.

    guard let message: String = diag[keys.description] else { return nil }

    var position: Position? = nil
    if let line: Int = diag[keys.line], let utf8Column: Int = diag[keys.column], line > 0, utf8Column > 0 {
      position = snapshot.positionOf(zeroBasedLine: line - 1, utf8Column: utf8Column - 1)
    } else if let utf8Offset: Int = diag[keys.offset] {
      position = snapshot.positionOf(utf8Offset: utf8Offset)
    }

    if position == nil {
      return nil
    }

    var severity: DiagnosticSeverity? = nil
    if let uid: sourcekitd_uid_t = diag[keys.severity] {
      switch uid {
      case values.diag_error:
        severity = .error
      case values.diag_warning:
        severity = .warning
      default:
        break
      }
    }

    var notes: [DiagnosticRelatedInformation]? = nil
    if let sknotes: SKResponseArray = diag[keys.diagnostics] {
      notes = []
      sknotes.forEach { (_, sknote) -> Bool in
        guard let note = getDiagnostic(sknote, for: snapshot) else { return true }
        notes?.append(DiagnosticRelatedInformation(
          location: note.range.lowerBound,
          message: note.message
        ))
        return true
      }
    }

    return Diagnostic(
      range: Range(position!),
      severity: severity,
      code: nil,
      source: "sourcekitd",
      message: message,
      relatedInformation: notes
    )
  }

  func publicDiagnostics(_ diags: SKResponseArray?, for snapshot: DocumentSnapshot) {
    // Note: we make the notification even if there are no diagnostics to clear the current state.
    var result: [Diagnostic] = []
    diags?.forEach { _, diag in
      if let diag = getDiagnostic(diag, for: snapshot) {
        result.append(diag)
      }
      return true
    }
    client.send(PublishDiagnostics(url: snapshot.document.url, diagnostics: result))
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
      publicDiagnostics(dict[keys.diagnostics], for: snapshot)
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
      referencesProvider: nil,
      documentHighlightProvider: true
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

    if let settings = buildSettingsProvider.settings(for: snapshot.document.url, language: snapshot.document.language) {
      req[keys.compilerargs] = settings.compilerArguments
    }

    guard let dict = self.sourcekitd.sendSync(req).success else {
      // Already logged failure.
      return
    }

    publicDiagnostics(dict[keys.diagnostics], for: snapshot)
  }

  func closeDocument(_ note: Notification<DidCloseTextDocument>) {
    documentManager.close(note)

    let req = SKRequestDictionary(sourcekitd: sourcekitd)
    req[keys.request] = requests.editor_close
    req[keys.name] = note.params.textDocument.url.path

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
      publicDiagnostics(dict[keys.diagnostics], for: snapshot)
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

    let completionPos = adjustCompletionLocation(req.params.position, in: snapshot)

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

    if let settings = buildSettingsProvider.settings(for: snapshot.document.url, language: snapshot.document.language) {
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

      let cancelled = !completions.forEach({ (i, value) -> Bool in
        // Check for cancellation periodically when there are many results.
        if i % 100 == 0, req.isCancelled {
          req.reply(LSPResult.failure(.cancelled))
          return false
        }

        guard let name: String = value[self.keys.description] else {
          return true // continue
        }

        let filterName: String? = value[self.keys.name]
        let insertText: String? = value[self.keys.sourcetext]

        let kind: sourcekitd_uid_t? = value[self.keys.kind]

        result.items.append(CompletionItem(
          label: name,
          detail: nil,
          sortText: nil,
          filterText: filterName,
          textEdit: nil,
          insertText: insertText.map { self.rewriteCompletionPlacholders($0) },
          insertTextFormat: .snippet,
          kind: kind?.asCompletionItemKind(self.values) ?? .value,
          deprecated: nil
        ))

        return true
      })

      if !cancelled {
        req.reply(result)
      }
    }

    // FIXME: cancellation
    _ = handle
  }

  func rewriteCompletionPlacholders(_ completion: String) -> String {
    if !completion.contains("<#") {
      return completion
    }

    var result = completion
    var index = 1
    while let start = result.range(of: "<#") {
      guard let end = result[start.upperBound...].range(of: "#>") else {
        log("invalid placholder in \(completion)", level: .debug)
        return completion
      }
      // FIXME: add name to placeholder
      result.replaceSubrange(start.lowerBound..<end.upperBound, with: "${\(index):value}")
      index += 1
    }
    return result
  }

  func adjustCompletionLocation(_ pos: Position, in snapshot: DocumentSnapshot) -> Position {
    guard let requestedLoc = snapshot.index(of: pos), requestedLoc != snapshot.text.startIndex else {
      return pos
    }

    let identifierChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    var prev = requestedLoc
    var loc = snapshot.text.index(before: requestedLoc)
    while identifierChars.contains(snapshot.text[loc].unicodeScalars.first!) {
      prev = loc
      loc = snapshot.text.index(before: loc)
    }

    // #aabccccccdddddd
    // ^^- prev  ^-requestedLoc
    // `- loc
    //
    // We offset the column by (requestedLoc - prev), which must be >=0 and on the same line.

    let delta = requestedLoc.encodedOffset - prev.encodedOffset

    return Position(line: pos.line, utf16index: pos.utf16index - delta)
  }

  func hover(_ req: Request<HoverRequest>) {

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
    skreq[keys.request] = requests.cursorinfo
    skreq[keys.offset] = offset
    skreq[keys.sourcefile] = snapshot.document.url.path

    // FIXME: should come from the internal document
    if let settings = buildSettingsProvider.settings(for: snapshot.document.url, language: snapshot.document.language) {
      skreq[keys.compilerargs] = settings.compilerArguments
    }

    let handle = sourcekitd.send(skreq) { [weak self] result in
      guard let self = self else { return }
      guard let dict = result.success else {
        req.reply(.failure(result.failure!))
        return
      }

      guard let _: sourcekitd_uid_t = dict[self.keys.kind] else {
        // Nothing to report.
        req.reply(nil)
        return
      }

      guard let name: String = dict[self.keys.name] else {
        // There is a cursor but we don't know how to deal with it.
        req.reply(nil)
        return
      }

      var result = "# \(name)"
      if let doc: String = dict[self.keys.doc_full_as_xml] {
        result += """

        \(orLog { try xmlDocumentationToMarkdown(doc) } ?? doc)
        """
      } else if let annotated: String = dict[self.keys.annotated_decl] {
        result += """

        \(orLog { try xmlDocumentationToMarkdown(annotated) } ?? annotated)
        """
      }

      let usr: String? = dict[self.keys.usr]

      var location: Location? = nil
      if let filepath: String = dict[self.keys.filepath],
         let offset: Int = dict[self.keys.offset],
         let pos = snapshot.positionOf(utf8Offset: offset)
      {
        location = Location(url: URL(fileURLWithPath: filepath), range: Range(pos))
      }

      req.reply(HoverResponse(
        contents: MarkupContent(kind: .markdown, value: result),
        range: nil,
        usr: usr,
        definition: location
      ))
    }

    // FIXME: cancellation
    _ = handle
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

    // FIXME: should come from the internal document
    if let settings = buildSettingsProvider.settings(for: snapshot.document.url, language: snapshot.document.language) {
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

      results.forEach { i, value in
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
}

extension DocumentSnapshot {

  func utf8Offset(of pos: Position) -> Int? {
    return lineTable.utf8OffsetOf(line: pos.line, utf16Column: pos.utf16index)
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

func makeLocalSwiftServer(client: MessageHandler, sourcekitd: AbsolutePath, buildSettings: BuildSettingsProvider?) throws -> Connection {

  let connectionToSK = LocalConnection()
  let connectionToClient = LocalConnection()

  let server = try SwiftLanguageServer(
    client: connectionToClient,
    sourcekitd: sourcekitd,
    buildSettingsProvider: buildSettings ?? BuildSettingsProviderList()
  )

  connectionToSK.start(handler: server)
  connectionToClient.start(handler: client)

  return connectionToSK
}

extension sourcekitd_uid_t {
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
}
