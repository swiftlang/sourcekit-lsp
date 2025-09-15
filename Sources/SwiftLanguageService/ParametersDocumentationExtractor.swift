//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Markdown

/// Extracts parameter documentation from a markdown string.
///
/// The parameter extraction implementation is almost ported from the implementation in the Swift compiler codebase.
///
/// The problem with doing that in the Swift compiler codebase is that once you parse a the comment as markdown into
/// a `Document` you cannot easily convert it back into markdown (we'd need to write our own markdown formatter).
/// Besides, `cmark` doesn't handle Doxygen commands.
///
/// We considered using `swift-docc` but we faced some problems with it:
///
/// 1. We would need to refactor existing use of `swift-docc` in SourceKit-LSP to reuse some of that logic here besides
///    providing the required arguments.
/// 2. The result returned by DocC can't be directly converted to markdown, we'd need to provide our own DocC markdown renderer.
///
/// Implementing this using `swift-markdown` allows us to easily parse the comment, process it, convert it back to markdown.
/// It also provides minimal parsing for Doxygen commands (we're only interested in `\param`) allowing us to use the same
/// implementation for Clang-based declarations.
///
/// Although this approach involves code duplication, it's simple enough for the initial implementation. We should consider
/// `swift-docc` in the future.
private struct ParametersDocumentationExtractor {
  struct Parameter {
    let name: String
    let documentation: String
  }

  /// Extracts parameter documentation from a markdown string.
  ///
  /// - Returns: A tuple containing the extracted parameters and the remaining markdown.
  func extract(from markdown: String) -> (parameters: [String: String], remaining: String) {
    let document = Document(parsing: markdown, options: [.parseBlockDirectives, .parseMinimalDoxygen])

    var parameters: [String: String] = [:]
    var remainingBlocks: [any BlockMarkup] = []

    for block in document.blockChildren {
      switch block {
      case let unorderedList as UnorderedList:
        let (newUnorderedList, params) = extract(from: unorderedList)
        if let newUnorderedList {
          remainingBlocks.append(newUnorderedList)
        }

        for param in params {
          parameters[param.name] = param.documentation
        }

      case let doxygenParameter as DoxygenParameter:
        let param = extract(from: doxygenParameter)
        parameters[param.name] = param.documentation

      default:
        remainingBlocks.append(block)
      }
    }

    let remaining = Document(remainingBlocks).format()

    return (parameters, remaining)
  }

  /// Extracts parameter documentation from a Doxygen parameter command.
  private func extract(from doxygenParameter: DoxygenParameter) -> Parameter {
    return Parameter(
      name: doxygenParameter.name,
      documentation: Document(doxygenParameter.blockChildren).format(),
    )
  }

  /// Extracts parameter documentation from an unordered list.
  ///
  /// - Returns: A new UnorderedList with the items that were not added to the parameters if any.
  private func extract(from unorderedList: UnorderedList) -> (remaining: UnorderedList?, parameters: [Parameter]) {
    var parameters: [Parameter] = []
    var newItems: [ListItem] = []

    for item in unorderedList.listItems {
      if let param = extractSingle(from: item) {
        parameters.append(param)
      } else if let params = extractOutline(from: item) {
        parameters.append(contentsOf: params)
      } else {
        newItems.append(item)
      }
    }

    if newItems.isEmpty {
      return (remaining: nil, parameters: parameters)
    }

    return (remaining: UnorderedList(newItems), parameters: parameters)
  }

  /// Parameter documentation from a `Parameters:` outline.
  ///
  /// Example:
  /// ```markdown
  /// - Parameters:
  ///   - param: description
  /// ```
  ///
  /// - Returns: True if the list item has parameter outline documentation, false otherwise.
  private func extractOutline(from listItem: ListItem) -> [Parameter]? {
    guard let firstChild = listItem.child(at: 0) as? Paragraph,
      let headingText = firstChild.child(at: 0) as? Text
    else {
      return nil
    }

    guard headingText.string.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("parameters:") else {
      return nil
    }

    return listItem.children.flatMap { child in
      guard let nestedList = child as? UnorderedList else {
        return [] as [Parameter]
      }

      return nestedList.listItems.compactMap(extractOutlineItem)
    }
  }

  /// Extracts parameter documentation from a single parameter.
  ///
  /// Example:
  /// ```markdown
  /// - Parameter param: description
  /// ```
  ///
  /// - Returns: True if the list item has single parameter documentation, false otherwise.
  private func extractSingle(from listItem: ListItem) -> Parameter? {
    guard let paragraph = listItem.child(at: 0) as? Paragraph,
      let paragraphText = paragraph.child(at: 0) as? Text
    else {
      return nil
    }

    let parameterPrefix = "parameter "
    let paragraphContent = paragraphText.string

    guard paragraphContent.count >= parameterPrefix.count else {
      return nil
    }

    let prefixEnd = paragraphContent.index(paragraphContent.startIndex, offsetBy: parameterPrefix.count)
    let potentialMatch = paragraphContent[..<prefixEnd].lowercased()

    guard potentialMatch == parameterPrefix else {
      return nil
    }

    let remainingContent = String(paragraphContent[prefixEnd...]).trimmingCharacters(in: .whitespaces)

    return extractParam(firstTextContent: remainingContent, listItem: listItem)
  }

  /// Extracts a parameter field from a list item (used for parameter outline items)
  private func extractOutlineItem(from listItem: ListItem) -> Parameter? {
    guard let paragraph = listItem.child(at: 0) as? Paragraph else {
      return nil
    }

    guard let paragraphText = paragraph.child(at: 0) as? Text else {
      return nil
    }

    return extractParam(firstTextContent: paragraphText.string, listItem: listItem)
  }

  /// Extracts a parameter field from a list item provided the relevant first text content allowing reuse in ``extractOutlineItem`` and ``extractSingle``
  ///
  /// - Parameters:
  ///   - firstTextContent: The content of the first text child of the list item's first paragraph
  ///   - listItem: The list item to extract the parameter from
  ///
  /// - Returns: A tuple containing the parameter name and documentation if a parameter was found, nil otherwise.
  private func extractParam(
    firstTextContent: String,
    listItem: ListItem
  ) -> Parameter? {
    guard let paragraph = listItem.child(at: 0) as? Paragraph else {
      return nil
    }

    let components = firstTextContent.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

    guard components.count == 2 else {
      return nil
    }

    let name = String(components[0]).trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else {
      return nil
    }

    let remainingFirstTextContent = String(components[1]).trimmingCharacters(in: .whitespaces)
    let remainingParagraphChildren = [Text(remainingFirstTextContent)] + paragraph.inlineChildren.dropFirst()
    let remainingChildren = [Paragraph(remainingParagraphChildren)] + listItem.blockChildren.dropFirst()
    let documentation = Document(remainingChildren).format()

    return Parameter(name: name, documentation: documentation)
  }
}

/// Extracts parameter documentation from markdown text.
///
/// - Parameter markdown: The markdown text to extract parameters from
/// - Returns: A tuple containing the extracted parameters dictionary and the remaining markdown text
package func extractParametersDocumentation(from markdown: String) -> ([String: String], String) {
  let extractor = ParametersDocumentationExtractor()
  return extractor.extract(from: markdown)
}
