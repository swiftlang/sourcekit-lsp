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

public struct SignatureHelpRequest: TextDocumentRequest {
  public static var method: String = "textDocument/signatureHelp"
  public typealias Response = SignatureHelp?

  /// The document in which the given symbol is located.
  public var textDocument: TextDocumentIdentifier

  /// The document location of a given symbol.
  public var position: Position

  /// The signature help context. This is only available if the client
  /// specifies to send this using the client capability
  /// `textDocument.signatureHelp.contextSupport === true`
  public var context: SignatureHelpContext?

  public init(textDocument: TextDocumentIdentifier, position: Position, context: SignatureHelpContext? = nil) {
    self.textDocument = textDocument
    self.position = position
    self.context = context
  }
}


/// How a signature help was triggered.
public struct SignatureHelpTriggerKind: RawRepresentable, Codable, Hashable {
  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// Signature help was invoked manually by the user or by a command.
  public static let invoked = SignatureHelpTriggerKind(rawValue: 1)

  /// Signature help was triggered by a trigger character.
  public static let triggerCharacter = SignatureHelpTriggerKind(rawValue: 2)

  /// Signature help was triggered by the cursor moving or by the document
  /// content changing.
  public static let contentChange = SignatureHelpTriggerKind(rawValue: 3)
}

/// Additional information about the context in which a signature help request
/// was triggered.
public struct SignatureHelpContext: Codable, Hashable {
  /// Action that caused signature help to be triggered.
  public var triggerKind: SignatureHelpTriggerKind

  /// Character that caused signature help to be triggered.
  ///
  /// This is undefined when triggerKind !==
  /// SignatureHelpTriggerKind.TriggerCharacter
  public var triggerCharacter: String?

  /// `true` if signature help was already showing when it was triggered.
  ///
  /// Retriggers occur when the signature help is already active and can be
  /// caused by actions such as typing a trigger character, a cursor move, or
  /// document content changes.
  public var isRetrigger: Bool

  /// The currently active `SignatureHelp`.
  ///
  /// The `activeSignatureHelp` has its `SignatureHelp.activeSignature` field
  /// updated based on the user navigating through available signatures.
  public var activeSignatureHelp: SignatureHelp?

  public init(triggerKind: SignatureHelpTriggerKind, triggerCharacter: String? = nil, isRetrigger: Bool, activeSignatureHelp: SignatureHelp? = nil) {
    self.triggerKind = triggerKind
    self.triggerCharacter = triggerCharacter
    self.isRetrigger = isRetrigger
    self.activeSignatureHelp = activeSignatureHelp
  }
}

/// Signature help represents the signature of something
/// callable. There can be multiple signature but only one
/// active and only one active parameter.
public struct SignatureHelp: ResponseType, Hashable {
  /// One or more signatures. If no signatures are available the signature help
  /// request should return `null`.
  public var signatures: [SignatureInformation]

  /// The active signature. If omitted or the value lies outside the
  /// range of `signatures` the value defaults to zero or is ignore if
  /// the `SignatureHelp` as no signatures.
  ///
  /// Whenever possible implementors should make an active decision about
  /// the active signature and shouldn't rely on a default value.
  ///
  /// In future version of the protocol this property might become
  /// mandatory to better express this.
  public var activeSignature: Int?

  /// The active parameter of the active signature. If omitted or the value
  /// lies outside the range of `signatures[activeSignature].parameters`
  /// defaults to 0 if the active signature has parameters. If
  /// the active signature has no parameters it is ignored.
  /// In future version of the protocol this property might become
  /// mandatory to better express the active parameter if the
  /// active signature does have any.
  public var activeParameter: Int?

  public init(signatures: [SignatureInformation], activeSignature: Int? = nil, activeParameter: Int? = nil) {
    self.signatures = signatures
    self.activeSignature = activeSignature
    self.activeParameter = activeParameter
  }
}

/// Represents the signature of something callable. A signature
/// can have a label, like a function-name, a doc-comment, and
/// a set of parameters.
public struct SignatureInformation: Codable, Hashable {
  /// The label of this signature. Will be shown in
  /// the UI.
  public var label: String

  /// The human-readable doc-comment of this signature. Will be shown
  /// in the UI but can be omitted.
  public var documentation: StringOrMarkupContent?

  /// The parameters of this signature.
  public var parameters: [ParameterInformation]?

  /// The index of the active parameter.
  ///
  /// If provided, this is used in place of `SignatureHelp.activeParameter`.
  public var activeParameter: Int?

  public init(label: String, documentation: StringOrMarkupContent? = nil, parameters: [ParameterInformation]? = nil, activeParameter: Int? = nil) {
    self.label = label
    self.documentation = documentation
    self.parameters = parameters
    self.activeParameter = activeParameter
  }
}

/// Represents a parameter of a callable-signature. A parameter can
/// have a label and a doc-comment.
public struct ParameterInformation: Codable, Hashable {
  public enum Label: Codable, Hashable {
    case string(String)
    case offsets(start: Int, end: Int)

    public init(from decoder: Decoder) throws {
      if let string = try? String(from: decoder) {
        self = .string(string)
      } else if let offsets = try? Array<Int>(from: decoder), offsets.count == 2 {
        self = .offsets(start: offsets[0], end: offsets[1])
      } else {
        let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or an array containing two integers")
        throw DecodingError.dataCorrupted(context)
      }
    }

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .string(let string):
        try string.encode(to: encoder)
      case .offsets(start: let start, end: let end):
        try [start, end].encode(to: encoder)
      }
    }
  }

  /// The label of this parameter information.
  ///
  /// Either a string or an inclusive start and exclusive end offsets within
  /// its containing signature label. (see SignatureInformation.label). The
  /// offsets are based on a UTF-16 string representation as `Position` and
  /// `Range` does.
  ///
  /// *Note*: a label of type string should be a substring of its containing
  /// signature label. Its intended use case is to highlight the parameter
  /// label part in the `SignatureInformation.label`.
  public var label: Label

  /// The human-readable doc-comment of this parameter. Will be shown
  /// in the UI but can be omitted.
  public var documentation: StringOrMarkupContent?

  public init(label: Label, documentation: StringOrMarkupContent? = nil) {
    self.label = label
    self.documentation = documentation
  }
}
