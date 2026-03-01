//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
@_spi(SourceKitLSP) import LanguageServerProtocol
import SKOptions
import SourceKitLSP
import SwiftSyntax

/// Insert a file header comment at the top of a file based on project configuration.
///
/// The template can use the following placeholders:
/// - `{filename}` - The name of the file
/// - `{project}` - The project name (extracted from workspace folder name)
/// - `{year}` - The current year
/// - `{date}` - The current date in YYYY-MM-DD format
/// - `{author}` - The author name (from configuration or system user)
/// - `{copyright}` - The copyright text (from configuration)
///
/// ## Before
///
/// ```swift
/// import Foundation
///
/// class MyClass {}
/// ```
///
/// ## After (with default template)
///
/// ```swift
/// //
/// //  MyClass.swift
/// //  MyProject
/// //
/// //  Created by Developer on 2026-01-01.
/// //  Copyright © 2026 MyCompany. All rights reserved.
/// //
///
/// import Foundation
///
/// class MyClass {}
/// ```
struct AddFileHeader: SyntaxCodeActionProvider {
  private static let defaultTemplate = """
    //
    //  {filename}
    //  {project}
    //
    //  Created by {author} on {date}.
    //  Copyright © {year} {copyright}. All rights reserved.
    //
    """

  static func codeActions(in scope: SyntaxCodeActionScope) -> [CodeAction] {
    if hasFileHeader(in: scope.file) {
      return []
    }

    guard isNearFileStart(scope: scope) else {
      return []
    }

    let uri = scope.snapshot.uri
    let filename = uri.fileURL?.lastPathComponent ?? uri.pseudoPath.components(separatedBy: "/").last ?? "Untitled"
    let projectName = extractProjectName(from: uri)
    let template = scope.fileHeaderOptions?.template ?? Self.defaultTemplate
    let author = scope.fileHeaderOptions?.author ?? ProcessInfo.processInfo.userName
    let copyright = scope.fileHeaderOptions?.copyright ?? projectName

    let headerContent = generateHeader(
      template: template,
      filename: filename,
      projectName: projectName,
      author: author,
      copyright: copyright
    )

    let insertPosition = Position(line: 0, utf16index: 0)

    return [
      CodeAction(
        title: "Add file header",
        kind: .refactorInline,
        edit: WorkspaceEdit(
          changes: [
            uri: [
              TextEdit(
                range: Range(insertPosition),
                newText: headerContent + "\n"
              )
            ]
          ]
        )
      )
    ]
  }

  private static func hasFileHeader(in file: SourceFileSyntax) -> Bool {
    guard let firstToken = file.firstToken(viewMode: .sourceAccurate) else {
      return false
    }
    for piece in firstToken.leadingTrivia {
      switch piece {
      case .lineComment, .blockComment, .docLineComment, .docBlockComment:
        return true
      case .newlines, .spaces, .tabs:
        continue
      default:
        return false
      }
    }
    return false
  }

  private static func isNearFileStart(scope: SyntaxCodeActionScope) -> Bool {
    if scope.request.range.lowerBound.line <= 5 {
      return true
    }
    if let firstStatement = scope.file.statements.first,
      let firstToken = firstStatement.firstToken(viewMode: .sourceAccurate),
      scope.range.lowerBound <= firstToken.endPosition
    {
      return true
    }
    return false
  }

  private static func extractProjectName(from uri: DocumentURI) -> String {
    guard let url = uri.fileURL else {
      return "MyProject"
    }
    var currentURL = url.deletingLastPathComponent()
    let fileManager = FileManager.default
    for _ in 0..<10 {
      let path = currentURL.path
      if fileManager.fileExists(atPath: currentURL.appendingPathComponent("Package.swift").path) {
        return currentURL.lastPathComponent
      }
      if let contents = try? fileManager.contentsOfDirectory(atPath: path),
        contents.contains(where: { $0.hasSuffix(".xcodeproj") })
      {
        return currentURL.lastPathComponent
      }
      if fileManager.fileExists(atPath: currentURL.appendingPathComponent(".git").path) {
        return currentURL.lastPathComponent
      }
      let parent = currentURL.deletingLastPathComponent()
      if parent == currentURL {
        break
      }
      currentURL = parent
    }
    return url.deletingLastPathComponent().lastPathComponent
  }

  private static func generateHeader(
    template: String,
    filename: String,
    projectName: String,
    author: String,
    copyright: String
  ) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let currentDate = dateFormatter.string(from: Date())

    let calendar = Calendar.current
    let currentYear = String(calendar.component(.year, from: Date()))

    var result = template
    result = result.replacingOccurrences(of: "{filename}", with: filename)
    result = result.replacingOccurrences(of: "{project}", with: projectName)
    result = result.replacingOccurrences(of: "{author}", with: author)
    result = result.replacingOccurrences(of: "{date}", with: currentDate)
    result = result.replacingOccurrences(of: "{year}", with: currentYear)
    result = result.replacingOccurrences(of: "{copyright}", with: copyright)

    return result
  }
}
