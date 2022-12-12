//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SourceKitD
import LanguageServerProtocol
import LSPLogging

struct InterfaceInfo {
  var contents: String
}

extension SwiftLanguageServer {
  public func openInterface(_ request: LanguageServerProtocol.Request<LanguageServerProtocol.OpenInterfaceRequest>) {
    let uri = request.params.textDocument.uri
    let moduleName = request.params.name
    self.queue.async {
      let interfaceFilePath = self.generatedInterfacesPath.appendingPathComponent("\(moduleName).swiftinterface")
      let interfaceDocURI = DocumentURI(interfaceFilePath)
      self._openInterface(request: request, uri: uri, name: moduleName, interfaceURI: interfaceDocURI) { result in
        switch result {
        case .success(let interfaceInfo):
          do {
            try interfaceInfo.contents.write(to: interfaceFilePath, atomically: true, encoding: String.Encoding.utf8)
            request.reply(.success(InterfaceDetails(uri: interfaceDocURI)))
          } catch {
            request.reply(.failure(ResponseError.unknown(error.localizedDescription)))
          }
        case .failure(let error):
          log("open interface failed: \(error)", level: .warning)
          request.reply(.failure(ResponseError(error)))
        }
      }
    }
  }
    
  /// Open the Swift interface for a module.
  ///
  /// - Parameters:
  ///   - request: The OpenInterfaceRequest.
  ///   - uri: The document whose compiler arguments should be used to generate the interface.
  ///   - name: The name of the module whose interface should be generated.
  ///   - interfaceURI: The file where the generated interface should be written.
  ///   - completion: Completion block to asynchronously receive the InterfaceInfo, or error.
  private func _openInterface(request: LanguageServerProtocol.Request<LanguageServerProtocol.OpenInterfaceRequest>,
                              uri: DocumentURI,
                              name: String,
                              interfaceURI: DocumentURI,
                              completion: @escaping (Swift.Result<InterfaceInfo, SKDError>) -> Void) {
    let keys = self.keys
    let skreq = SKDRequestDictionary(sourcekitd: sourcekitd)
    skreq[keys.request] = requests.editor_open_interface
    skreq[keys.modulename] = name
    skreq[keys.name] = interfaceURI.pseudoPath
    skreq[keys.synthesizedextensions] = 1
    if let compileCommand = self.commandsByFile[uri] {
      skreq[keys.compilerargs] = compileCommand.compilerArgs
    }
    
    let handle = self.sourcekitd.send(skreq, self.queue) { result in
      switch result {
      case .success(let dict):
        return completion(.success(InterfaceInfo(contents: dict[keys.sourcetext] ?? "")))
      case .failure(let error):
        return completion(.failure(error))
      }
    }
    
    if let handle = handle {
      request.cancellationToken.addCancellationHandler { [weak self] in
        self?.sourcekitd.cancel(handle)
      }
    }
  }
}
