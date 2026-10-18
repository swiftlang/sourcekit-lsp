//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) import SKLogging

#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reconstructs the plain text of a sourcekitd annotated-description string by dropping all XML markup and unescaping
/// XML entities.
///
/// sourcekitd's annotated completion label/type name is a fragment of XML (e.g. `<name>foo</name>(…)`) that is *not*
/// single-rooted and that XML-escapes `& < > " '`. A naive tag strip would therefore corrupt operators, generics like
/// `Set<Int>`, and quoted text, so we parse it with a streaming parser over a synthetic root element and concatenate
/// the character data, which the parser delivers already unescaped.
///
/// On a parse failure — which should not happen for well-formed compiler output — logs a fault and returns `xml`
/// unchanged.
func plainText(fromAnnotatedCompletionXML xml: String) -> String {
  guard let data = "<root>\(xml)</root>".data(using: .utf8) else {
    return xml
  }
  let parser = XMLParser(data: data)
  let delegate = AnnotatedCompletionTextParserDelegate()
  parser.delegate = delegate
  guard parser.parse() else {
    logger.fault(
      "Failed to parse annotated completion XML: \(parser.parserError?.localizedDescription ?? "unknown error", privacy: .public)"
    )
    return xml
  }
  return delegate.plainText
}

private final class AnnotatedCompletionTextParserDelegate: NSObject, XMLParserDelegate {
  var plainText: String = ""

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    plainText += string
  }
}
