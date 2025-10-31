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

package import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol

import struct TSCBasic.AbsolutePath

package extension TextDocumentIdentifier {
  init(_ url: URL) {
    self.init(DocumentURI(url))
  }
}

package extension AbsolutePath {
  var asURI: DocumentURI {
    return DocumentURI(asURL)
  }
}
