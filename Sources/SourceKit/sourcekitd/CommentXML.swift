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

import SKSupport
import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

enum CommentXMLError: Error {
  case noRootElement
}

/// Converts from sourcekit's XML documentation format to Markdown.
///
/// This code should go away and sourcekitd should return the Markdown directly.
public func xmlDocumentationToMarkdown(_ xmlString: String) throws -> String {
  let xml = try XMLDocument(xmlString: xmlString)
  guard let root = xml.rootElement() else {
    throw CommentXMLError.noRootElement
  }

  var convert = XMLToMarkdown()
  convert.out.reserveCapacity(xmlString.utf16.count)
  convert.toMarkdown(root)
  return convert.out
}

private struct XMLToMarkdown {
  var out: String = ""
  var indentCount: Int = 0
  let indentWidth: Int = 4
  var lineNumber: Int = 0
  var inParam: Bool = false

  mutating func newlineIfNeeded(count: Int = 1) {
    if !out.isEmpty && out.last! != "\n" {
      newline(count: count)
    }
  }

  mutating func newline(count: Int = 1) {
    out += String(repeating: "\n", count: count)
    out += String(repeating: " ", count: indentWidth * indentCount)
  }

  mutating func toMarkdown(_ node: XMLNode) {
    switch node.kind {
    case .element:
      toMarkdown(node as! XMLElement)
    default:
      out += node.stringValue ?? ""
    }
  }

  // [XMLNode]? is the type of XMLNode.children.
  mutating func toMarkdown(_ nodes: [XMLNode]?, separator: String = "") {
    nodes?.forEach {
      toMarkdown($0)
      out += separator
    }
  }

  mutating func toMarkdown(_ node: XMLElement) {
    switch node.name {
    case "Declaration":
      newlineIfNeeded(count: 2)
      out += "```\n"
      toMarkdown(node.children)
      out += "\n```\n\n---\n"
      
    case "Name", "USR", "Direction":
      break

    case "Abstract", "Para":
      if !inParam {
        newlineIfNeeded(count: 2)
      }
      toMarkdown(node.children)

    case "Discussion", "ResultDiscussion", "ThrowsDiscussion":
      if !inParam {
        newlineIfNeeded(count: 2)
      }
      out += "### "
      switch node.name {
      case "Discussion": out += "Discussion"
      case "ResultDiscussion": out += "Returns"
      case "ThrowsDiscussion": out += "Throws"
      default: fatalError("handled in outer switch")
      }
      newline(count: 2)
      toMarkdown(node.children)

    case "Parameters":
      newlineIfNeeded(count: 2)
      out += "- Parameters:"
      indentCount += 1
      toMarkdown(node.children)
      indentCount -= 1

    case "Parameter":
      guard let name = node.elements(forName: "Name").first else { break }
      newlineIfNeeded()
      out += "- "
      toMarkdown(name.children)
      if let discussion = node.elements(forName: "Discussion").first {
        out += ": "
        inParam = true
        toMarkdown(discussion.children)
        inParam = false
      }
      // FIXME: closure parameters would go here.

    case "CodeListing":
      lineNumber = 0
      newlineIfNeeded(count: 2)
      out += "```\n"
      toMarkdown(node.children, separator: "\n")
      out += "```"

    case "zCodeLineNumbered":
      lineNumber += 1
      out += "\(lineNumber).\t"
      toMarkdown(node.children)

    case "codeVoice":
      out += "`"
      toMarkdown(node.children)
      out += "`"

    case "emphasis":
      out += "*"
      toMarkdown(node.children)
      out += "*"

    case "bold":
      out += "**"
      toMarkdown(node.children)
      out += "**"

    case "h1", "h2", "h3", "h4", "h5", "h6":
      newlineIfNeeded(count: 2)
      let n = Int(node.name!.dropFirst())
      out += String(repeating: "#", count: n!)
      out += " "
      toMarkdown(node.children)
      out += "\n\n"

    default:
      toMarkdown(node.children)
    }
  }
}
