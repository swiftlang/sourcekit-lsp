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

import Dispatch
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import SKSupport
import SPMLibc
import SourceKit
import sourcekitd  // Not needed here, but fixes debugging...

Logger.shared.setLogLevel(environmentVariable: "SOURCEKIT_LOGGING")

let clientConnection = JSONRPCConection(
      inFD: STDIN_FILENO, outFD: STDOUT_FILENO, closeHandler: { exit(0) })

Logger.shared.addLogHandler { message, _ in
      clientConnection.send(LogMessage(type: .log, message: message))
}

let server = SourceKitServer(
      client: clientConnection, onExit: { clientConnection.close() })
clientConnection.start(receiveHandler: server)

dispatchMain()
