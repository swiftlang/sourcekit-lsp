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

@propertyWrapper
final class HeapBox<T> {
  var wrappedValue: T
  init(wrappedValue: T) {
    self.wrappedValue = wrappedValue
  }
}

/// JSON Schema representation for version draft-07
/// https://json-schema.org/draft-07/draft-handrews-json-schema-01
///
/// NOTE: draft-07 is the latest version of JSON Schema that is supported by
/// most of the tools. We may need to update this schema in the future.
struct JSONSchema: Encodable {
  enum CodingKeys: String, CodingKey {
    case _schema = "$schema"
    case id = "$id"
    case comment = "$comment"
    case title
    case type
    case description
    case properties
    case required
    case `enum`
    case items
    case additionalProperties
    case markdownDescription
    case markdownEnumDescriptions
    case oneOf
    case const
  }
  var _schema: String?
  var id: String?
  var comment: String?
  var title: String?
  var type: String?
  var description: String?
  var properties: [String: JSONSchema]?
  var required: [String]?
  var `enum`: [String]?
  @HeapBox
  var items: JSONSchema?
  @HeapBox
  var additionalProperties: JSONSchema?

  /// VSCode extension: Markdown formatted description for rich hover
  /// https://github.com/microsoft/vscode-wiki/blob/main/Setting-Descriptions.md
  var markdownDescription: String?
  /// VSCode extension: Markdown formatted descriptions for rich hover for enum values
  /// https://github.com/microsoft/vscode-wiki/blob/main/Setting-Descriptions.md
  var markdownEnumDescriptions: [String]?

  var oneOf: [JSONSchema]?
  var const: String?

  func encode(to encoder: any Encoder) throws {
    // Manually implement encoding to use `encodeIfPresent` for HeapBox-ed fields
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(_schema, forKey: ._schema)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encodeIfPresent(comment, forKey: .comment)
    try container.encodeIfPresent(title, forKey: .title)
    try container.encodeIfPresent(type, forKey: .type)
    try container.encodeIfPresent(description, forKey: .description)
    if let properties = properties, !properties.isEmpty {
      try container.encode(properties, forKey: .properties)
    }
    if let required = required, !required.isEmpty {
      try container.encode(required, forKey: .required)
    }
    try container.encodeIfPresent(`enum`, forKey: .enum)
    try container.encodeIfPresent(items, forKey: .items)
    try container.encodeIfPresent(additionalProperties, forKey: .additionalProperties)
    try container.encodeIfPresent(markdownDescription, forKey: .markdownDescription)
    if let markdownEnumDescriptions {
      try container.encode(markdownEnumDescriptions, forKey: .markdownEnumDescriptions)
    }
    if let oneOf, !oneOf.isEmpty {
      try container.encode(oneOf, forKey: .oneOf)
    }
    try container.encodeIfPresent(const, forKey: .const)
  }
}

struct JSONSchemaBuilder {
  let context: OptionSchemaContext

  func build(from typeSchema: OptionTypeSchama) throws -> JSONSchema {
    var schema = try buildJSONSchema(from: typeSchema)
    schema._schema = "http://json-schema.org/draft-07/schema#"
    return schema
  }

  private func buildJSONSchema(from typeSchema: OptionTypeSchama) throws -> JSONSchema {
    var schema = JSONSchema()
    switch typeSchema.kind {
    case .boolean: schema.type = "boolean"
    case .integer: schema.type = "integer"
    case .number: schema.type = "number"
    case .string: schema.type = "string"
    case .array(let value):
      schema.type = "array"
      schema.items = try buildJSONSchema(from: value)
    case .dictionary(let value):
      schema.type = "object"
      schema.additionalProperties = try buildJSONSchema(from: value)
    case .struct(let structInfo):
      schema.type = "object"
      var properties: [String: JSONSchema] = [:]
      var required: [String] = []
      for property in structInfo.properties {
        let propertyType = property.type
        var propertySchema = try buildJSONSchema(from: propertyType)
        propertySchema.description = property.description
        // As we usually use Markdown syntax for doc comments, set `markdownDescription`
        // too for better rendering in VSCode.
        propertySchema.markdownDescription = property.description
        properties[property.name] = propertySchema
        if !propertyType.isOptional {
          required.append(property.name)
        }
      }
      schema.properties = properties
      schema.required = required
    case .enum(let enumInfo):
      let hasAssociatedTypes = enumInfo.cases.contains { !($0.associatedProperties?.isEmpty ?? true) }

      if hasAssociatedTypes {
        let discriminatorFieldName = enumInfo.discriminatorFieldName ?? "type"
        var oneOfSchemas: [JSONSchema] = []

        for caseInfo in enumInfo.cases {
          var caseSchema = JSONSchema()
          caseSchema.type = "object"
          caseSchema.description = caseInfo.description
          caseSchema.markdownDescription = caseInfo.description

          var caseProperties: [String: JSONSchema] = [:]
          var caseRequired: [String] = [discriminatorFieldName]

          var discriminatorSchema = JSONSchema()
          discriminatorSchema.const = caseInfo.name
          caseProperties[discriminatorFieldName] = discriminatorSchema

          if let associatedProperties = caseInfo.associatedProperties {
            for property in associatedProperties {
              let propertyType = property.type
              var propertySchema = try buildJSONSchema(from: propertyType)
              propertySchema.description = property.description
              propertySchema.markdownDescription = property.description
              caseProperties[property.name] = propertySchema
              if !propertyType.isOptional {
                caseRequired.append(property.name)
              }
            }
          }

          caseSchema.properties = caseProperties
          caseSchema.required = caseRequired
          oneOfSchemas.append(caseSchema)
        }

        schema.oneOf = oneOfSchemas
      } else {
        schema.type = "string"
        schema.enum = enumInfo.cases.map(\.name)
        // Set `markdownEnumDescriptions` for better rendering in VSCode rich hover
        // Unlike `description`, `enumDescriptions` field is not a part of JSON Schema spec,
        // so we only set `markdownEnumDescriptions` here.
        if enumInfo.cases.contains(where: { $0.description != nil }) {
          schema.markdownEnumDescriptions = enumInfo.cases.map { $0.description ?? "" }
        }
      }
    }
    return schema
  }
}
