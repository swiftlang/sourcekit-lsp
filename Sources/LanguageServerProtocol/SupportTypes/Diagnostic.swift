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

/// The serverity level of a Diagnostic, between hint and error.
public enum DiagnosticSeverity: Int, Codable, Hashable {
  case error = 1
  case warning = 2
  case information = 3
  case hint = 4
}

/// A unique diagnostic code, which may be used identifier the diagnostic in e.g. documentation.
public enum DiagnosticCode: Hashable {
  case number(Int)
  case string(String)
}

/// Captures a description of a diagnostic error code.
public struct CodeDescription: Codable, Hashable {

  /// A URI to open with more information about the diagnostic.
  public var href: DocumentURI

  public init(href: DocumentURI) {
    self.href = href
  }
}

/// A diagnostic message such a compiler error or warning.
public struct Diagnostic: Codable, Hashable {

  /// The primary position/range of the diagnostic.
  @CustomCodable<PositionRange>
  public var range: Range<Position>

  /// Whether this is a warning, error, etc.
  public var severity: DiagnosticSeverity?

  /// The "code" of the diagnostice, which might be a number or string, typically providing a unique
  /// way to reference the diagnostic in e.g. documentation.
  public var code: DiagnosticCode?

  /// An optional description of the diagnostic code.
  public var codeDescription: CodeDescription?

  /// A human-readable description of the source of this diagnostic, e.g. "sourcekitd"
  public var source: String?

  /// The diagnostic message.
  public var message: String

  /// Additional metadata about the diagnostic.
  public var tags: [DiagnosticTag]?

  /// Related diagnostic notes.
  public var relatedInformation: [DiagnosticRelatedInformation]?

  /// A data entry field that is preserved between a
  /// `textDocument/publishDiagnostics` notification and
  /// `textDocument/codeAction` request.
  public var data: LSPAny?

  /// All the code actions that address this diagnostic.
  /// **LSP Extension from clangd**.
  public var codeActions: [CodeAction]?

  public init(
    range: Range<Position>,
    severity: DiagnosticSeverity?,
    code: DiagnosticCode? = nil,
    codeDescription: CodeDescription? = nil,
    source: String?,
    message: String,
    tags: [DiagnosticTag]? = nil,
    relatedInformation: [DiagnosticRelatedInformation]? = nil,
    data: LSPAny? = nil,
    codeActions: [CodeAction]? = nil)
  {
    self._range = CustomCodable<PositionRange>(wrappedValue: range)
    self.severity = severity
    self.code = code
    self.codeDescription = codeDescription
    self.source = source
    self.message = message
    self.tags = tags
    self.relatedInformation = relatedInformation
    self.data = data
    self.codeActions = codeActions
  }
}

/// A small piece of metadata about a diagnostic that lets editors e.g. style the diagnostic
/// in a special way.
public struct DiagnosticTag: RawRepresentable, Codable, Hashable {
  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  /// Unused or unnecessary code.
  ///
  /// Clients are allowed to render diagnostics with this tag faded out
  /// instead of having an error squiggle.
  public static let unnecessary: DiagnosticTag = DiagnosticTag(rawValue: 1)

  /// Deprecated or obsolete code.
  ///
  /// Clients are allowed to rendered diagnostics with this tag strike through.
  public static let deprecated: DiagnosticTag = DiagnosticTag(rawValue: 2)
}

/// A 'note' diagnostic attached to a primary diagonstic that provides additional information.
public struct DiagnosticRelatedInformation: Codable, Hashable {

  /// The location of this related diagnostic information.
  public var location: Location

  /// The message of this related diagnostic information.
  public var message: String

  /// All the code actions that address the parent diagnostic via this note.
  /// **LSP Extension from clangd**.
  public var codeActions: [CodeAction]?

  public init(location: Location, message: String, codeActions: [CodeAction]? = nil) {
    self.location = location
    self.message = message
    self.codeActions = codeActions
  }
}

extension DiagnosticCode: Codable {
  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let intValue = try? value.decode(Int.self) {
      self = .number(intValue)
    } else if let strValue = try? value.decode(String.self) {
      self = .string(strValue)
    } else {
      throw MessageDecodingError.invalidRequest("could not decode diagnostic code")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    }
  }
}

extension DiagnosticCode: CustomStringConvertible {
  public var description: String {
    switch self {
    case .number(let n): return String(n)
    case .string(let s): return "\"\(s)\""
    }
  }
}
