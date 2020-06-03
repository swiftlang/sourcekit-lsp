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

/// The color presentation request is sent from the client to the server to obtain 
/// a list of presentations for a color value at a given location. Clients can 
/// use the result to modify a color reference, or show in a color picker 
/// and let users pick one of the presentations
///
/// - Parameters:
///   - textDocument: The document to request presentations for.
///   - color: The color information to request presentations for.
///   - range: The range where the color would be inserted. Serves as a context.
///
/// - Returns: A list of color presentations for the given document.
public struct ColorPresentationRequest: TextDocumentRequest, Hashable {
  public static let method: String = "textDocument/colorPresentation"
  public typealias Response = [ColorPresentation]

  /// The document to request presentations for.
  public var textDocument: TextDocumentIdentifier

  /// The color information to request presentations for.
  public var color: Color

  /// The range where the color would be inserted. Serves as a context.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  public init(textDocument: TextDocumentIdentifier, color: Color, range: Range<Position>) {
    self.textDocument = textDocument
    self.color = color
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
  }
}

public struct ColorPresentation: ResponseType, Hashable {
  /// The label of this color presentation. It will be shown on the color
  /// picker header. By default this is also the text that is inserted when 
  /// selecting this color presentation.
  public var label: String

  /// An edit which is applied to a document when selecting this
  /// presentation for the color.  When `falsy` the label is used.
  public var textEdit: TextEdit?

  /// An optional array of additional text edits that are applied when
  /// selecting this color presentation. Edits must not overlap with 
  /// the main edit nor with themselves.
  public var additionalTextEdits: [TextEdit]?

  public init(label: String, textEdit: TextEdit?, additionalTextEdits: [TextEdit]?) {
    self.label = label
    self.textEdit = textEdit
    self.additionalTextEdits = additionalTextEdits
  }
}
