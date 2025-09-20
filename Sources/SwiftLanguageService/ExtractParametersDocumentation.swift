//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Markdown

private struct Parameter {
  let name: String
  let documentation: String
}

/// Extracts parameter documentation from a Doxygen parameter command.
private func extractParameter(from doxygenParameter: DoxygenParameter) -> Parameter {
  return Parameter(
    name: doxygenParameter.name,
    documentation: Document(doxygenParameter.blockChildren).format(),
  )
}

/// Extracts parameter documentation from an unordered list.
///
/// - Returns: A new ``UnorderedList`` with the items that were not added to the parameters if any.
private func extractParameters(
  from unorderedList: UnorderedList
) -> (remaining: UnorderedList?, parameters: [Parameter]) {
  var parameters: [Parameter] = []
  var newItems: [ListItem] = []

  for item in unorderedList.listItems {
    if let param = extractSingleParameter(from: item) {
      parameters.append(param)
    } else if let params = extractParametersOutline(from: item) {
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
/// - Returns: The extracted parameters if any, nil otherwise.
private func extractParametersOutline(from listItem: ListItem) -> [Parameter]? {
  guard
    let firstChild = listItem.child(at: 0) as? Paragraph,
    let headingText = firstChild.child(at: 0) as? Text,
    headingText.string.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("parameters:")
  else {
    return nil
  }

  return listItem.children.flatMap { child in
    guard let nestedList = child as? UnorderedList else {
      return [] as [Parameter]
    }

    return nestedList.listItems.compactMap { extractParameter(listItem: $0) }
  }
}

/// Extracts parameter documentation from a single parameter.
///
/// Example:
/// ```markdown
/// - Parameter param: description
/// ```
///
/// - Returns: The extracted parameter if any, nil otherwise.
private func extractSingleParameter(from listItem: ListItem) -> Parameter? {
  guard let paragraph = listItem.child(at: 0) as? Paragraph,
    let paragraphText = paragraph.child(at: 0) as? Text
  else {
    return nil
  }

  let parameterPrefix = "parameter "
  let paragraphContent = paragraphText.string

  guard
    let prefixEnd = paragraphContent.index(
      paragraphContent.startIndex,
      offsetBy: parameterPrefix.count,
      limitedBy: paragraphContent.endIndex
    )
  else {
    return nil
  }

  let potentialMatch = paragraphContent[..<prefixEnd].lowercased()

  guard potentialMatch == parameterPrefix else {
    return nil
  }

  let remainingContent = String(paragraphContent[prefixEnd...]).trimmingCharacters(in: .whitespaces)

  // Remove the "Parameter " prefix from the list item so we can extract the parameter's documentation using `extractParameter(listItem:)`
  var remainingParagraph = paragraph
  if remainingContent.isEmpty {
    // Drop the Text node if it's empty. This allows `extractParameterWithRawIdentifier` to handle both single parameters
    // and parameter outlines uniformly.
    remainingParagraph.replaceChildrenInRange(0..<1, with: [])
  } else {
    remainingParagraph.replaceChildrenInRange(0..<1, with: [Text(remainingContent)])
  }

  var remainingListItem = listItem
  remainingListItem.replaceChildrenInRange(0..<1, with: [remainingParagraph])

  return extractParameter(listItem: remainingListItem)
}

/// Extracts a parameter field from a list item.
///
/// - Parameters:
///   - listItem: The list item to extract the parameter from
///
/// - Returns: The extracted parameter if any, nil otherwise.
private func extractParameter(listItem: ListItem) -> Parameter? {
  guard let paragraph = listItem.child(at: 0) as? Paragraph else {
    return nil
  }

  guard let firstText = paragraph.child(at: 0) as? Text else {
    return extractParameterWithRawIdentifier(from: listItem)
  }

  let components = firstText.string.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

  guard components.count == 2 else {
    return extractParameterWithRawIdentifier(from: listItem)
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

/// Extracts a parameter with its name as a raw identifier.
///
/// Example:
/// ```markdown
/// - Parameter `foo bar`: documentation
/// - Parameters:
///   - `foo bar`: documentation
/// ```
///
/// - Parameters:
///   - listItem: The list item to extract the parameter from
private func extractParameterWithRawIdentifier(from listItem: ListItem) -> Parameter? {
  guard let paragraph = listItem.child(at: 0) as? Paragraph,
    let rawIdentifier = paragraph.child(at: 0) as? InlineCode,
    let text = paragraph.child(at: 1) as? Text
  else {
    return nil
  }

  let textContent = text.string.trimmingCharacters(in: .whitespaces)

  guard textContent.hasPrefix(":") else {
    return nil
  }

  let remainingTextContent = String(textContent.dropFirst()).trimmingCharacters(in: .whitespaces)
  let remainingParagraphChildren =
    [Text(remainingTextContent)] + paragraph.inlineChildren.dropFirst(2)
  let remainingChildren = [Paragraph(remainingParagraphChildren)] + listItem.blockChildren.dropFirst(1)
  let documentation = Document(remainingChildren).format()

  return Parameter(name: rawIdentifier.code, documentation: documentation)
}

/// Extracts parameter documentation from markdown text.
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
///
/// - Parameter markdown: The markdown text to extract parameters from
/// - Returns: A tuple containing the extracted parameters dictionary and the remaining markdown text
package func extractParametersDocumentation(
  from markdown: String
) -> (parameters: [String: String], remaining: String) {
  let document = Document(parsing: markdown, options: [.parseBlockDirectives, .parseMinimalDoxygen])

  var parameters: [String: String] = [:]
  var remainingBlocks: [any BlockMarkup] = []

  for block in document.blockChildren {
    switch block {
    case let unorderedList as UnorderedList:
      let (newUnorderedList, params) = extractParameters(from: unorderedList)
      if let newUnorderedList {
        remainingBlocks.append(newUnorderedList)
      }

      for param in params {
        // If duplicate parameter documentation is found, keep the first one following swift-docc's behavior
        parameters[param.name] = parameters[param.name] ?? param.documentation
      }

    case let doxygenParameter as DoxygenParameter:
      let param = extractParameter(from: doxygenParameter)
      // If duplicate parameter documentation is found, keep the first one following swift-docc's behavior
      parameters[param.name] = parameters[param.name] ?? param.documentation

    default:
      remainingBlocks.append(block)
    }
  }

  let remaining = Document(remainingBlocks).format()

  return (parameters: parameters, remaining: remaining)
}
