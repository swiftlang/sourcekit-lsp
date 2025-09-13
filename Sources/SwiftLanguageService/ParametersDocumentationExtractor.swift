import Foundation
import Markdown

private struct ParametersDocumentationExtractor {
  private var parameters = [String: String]()

  /// Extracts parameter documentation from a markdown string.
  ///
  /// - Returns: A tuple containing the extracted parameters and the remaining markdown.
  mutating func extract(from markdown: String) -> (parameters: [String: String], remaining: String) {
    let document = Document(parsing: markdown, options: [.parseBlockDirectives, .parseMinimalDoxygen])

    var remainingBlocks = [any BlockMarkup]()

    for block in document.blockChildren {
      switch block {
      case let unorderedList as UnorderedList:
        if let newUnorderedList = extract(from: unorderedList) {
          remainingBlocks.append(newUnorderedList)
        }
      case let doxygenParameter as DoxygenParameter:
        extract(from: doxygenParameter)
      default:
        remainingBlocks.append(block)
      }
    }

    let remaining = Document(remainingBlocks).format()

    return (parameters, remaining)
  }

  /// Extracts parameter documentation from a Doxygen parameter command.
  private mutating func extract(from doxygenParameter: DoxygenParameter) {
    parameters[doxygenParameter.name] = Document(doxygenParameter.blockChildren).format()
  }

  /// Extracts parameter documentation from an unordered list.
  ///
  /// - Returns: A new UnorderedList with the items that were not added to the parameters if any.
  private mutating func extract(from unorderedList: UnorderedList) -> UnorderedList? {
    var newItems = [ListItem]()

    for item in unorderedList.listItems {
      if extractSingle(from: item) || extractOutline(from: item) {
        continue
      }

      newItems.append(item)
    }

    if newItems.isEmpty {
      return nil
    }

    return UnorderedList(newItems)
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
  private mutating func extractOutline(from listItem: ListItem) -> Bool {
    guard let firstChild = listItem.child(at: 0) as? Paragraph,
      let headingText = firstChild.child(at: 0) as? Text
    else {
      return false
    }

    let parametersPrefix = "parameters:"
    let headingContent = headingText.string.trimmingCharacters(in: .whitespaces)

    guard headingContent.lowercased().hasPrefix(parametersPrefix) else {
      return false
    }

    for child in listItem.children {
      guard let nestedList = child as? UnorderedList else {
        continue
      }

      for nestedItem in nestedList.listItems {
        if let parameter = extractOutlineItem(from: nestedItem) {
          parameters[parameter.name] = parameter.documentation
        }
      }
    }

    return true
  }

  /// Extracts parameter documentation from a single parameter.
  ///
  /// Example:
  /// ```markdown
  /// - Parameter param: description
  /// ```
  ///
  /// - Returns: True if the list item has single parameter documentation, false otherwise.
  private mutating func extractSingle(from listItem: ListItem) -> Bool {
    guard let paragraph = listItem.child(at: 0) as? Paragraph,
      let paragraphText = paragraph.child(at: 0) as? Text
    else {
      return false
    }

    let parameterPrefix = "parameter "
    let paragraphContent = paragraphText.string

    guard paragraphContent.count >= parameterPrefix.count else {
      return false
    }

    let prefixEnd = paragraphContent.index(paragraphContent.startIndex, offsetBy: parameterPrefix.count)
    let potentialMatch = paragraphContent[..<prefixEnd].lowercased()

    guard potentialMatch == parameterPrefix else {
      return false
    }

    let remainingContent = String(paragraphContent[prefixEnd...]).trimmingCharacters(in: .whitespaces)

    guard let parameter = extractParam(firstTextContent: remainingContent, listItem: listItem) else {
      return false
    }

    parameters[parameter.name] = parameter.documentation

    return true
  }

  /// Extracts a parameter field from a list item (used for parameter outline items)
  private func extractOutlineItem(from listItem: ListItem) -> (name: String, documentation: String)? {
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
  ) -> (name: String, documentation: String)? {
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

    return (name, documentation)
  }
}

/// Extracts parameter documentation from markdown text.
///
/// - Parameter markdown: The markdown text to extract parameters from
/// - Returns: A tuple containing the extracted parameters dictionary and the remaining markdown text
package func extractParametersDocumentation(from markdown: String) -> ([String: String], String) {
  var extractor = ParametersDocumentationExtractor()
  return extractor.extract(from: markdown)
}
