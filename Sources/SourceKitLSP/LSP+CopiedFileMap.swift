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

package import BuildServerIntegration
@_spi(SourceKitLSP) package import LanguageServerProtocol

extension Location {
  package func adjusted(for copiedFileMap: CopiedFileMap) -> Location {
    return Location(uri: copiedFileMap.adjustedURI(for: uri), range: range)
  }
}

extension [Location] {
  package func adjusted(for copiedFileMap: CopiedFileMap) -> [Location] {
    return self.map { $0.adjusted(for: copiedFileMap) }
  }
}

extension WorkspaceEdit {
  package func adjusted(for copiedFileMap: CopiedFileMap) -> WorkspaceEdit {
    var edit = self
    if let changes = self.changes {
      var newChanges: [DocumentURI: [TextEdit]] = [:]
      for (uri, edits) in changes {
        newChanges[copiedFileMap.adjustedURI(for: uri), default: []] += edits
      }
      edit.changes = newChanges
    }
    if let documentChanges = self.documentChanges {
      edit.documentChanges = documentChanges.map { change in
        switch change {
        case .textDocumentEdit(var textEdit):
          textEdit.textDocument.uri = copiedFileMap.adjustedURI(for: textEdit.textDocument.uri)
          return .textDocumentEdit(textEdit)
        case .createFile(var create):
          create.uri = copiedFileMap.adjustedURI(for: create.uri)
          return .createFile(create)
        case .renameFile(var rename):
          rename.oldUri = copiedFileMap.adjustedURI(for: rename.oldUri)
          rename.newUri = copiedFileMap.adjustedURI(for: rename.newUri)
          return .renameFile(rename)
        case .deleteFile(var delete):
          delete.uri = copiedFileMap.adjustedURI(for: delete.uri)
          return .deleteFile(delete)
        }
      }
    }
    return edit
  }
}

extension LocationsOrLocationLinksResponse {
  package func adjusted(for copiedFileMap: CopiedFileMap) -> LocationsOrLocationLinksResponse {
    switch self {
    case .locations(let locations):
      return .locations(locations.adjusted(for: copiedFileMap))
    case .locationLinks(let locationLinks):
      return .locationLinks(
        locationLinks.map { link in
          let adjustedTargetURI = copiedFileMap.adjustedURI(for: link.targetUri)
          return LocationLink(
            originSelectionRange: link.originSelectionRange,
            targetUri: adjustedTargetURI,
            targetRange: link.targetRange,
            targetSelectionRange: link.targetSelectionRange
          )
        }
      )
    }
  }
}

extension TypeHierarchyItem {
  package func adjusted(for copiedFileMap: CopiedFileMap) -> TypeHierarchyItem {
    let adjustedURI = copiedFileMap.adjustedURI(for: uri)
    let adjustedData =
      HierarchyItemData(fromLSPAny: data).map { itemData in
        HierarchyItemData(uri: adjustedURI, usr: itemData.usr).encodeToLSPAny()
      } ?? self.data
    return TypeHierarchyItem(
      name: name,
      kind: kind,
      tags: tags,
      detail: detail,
      uri: adjustedURI,
      range: range,
      selectionRange: selectionRange,
      data: adjustedData
    )
  }
}

extension CallHierarchyItem {
  package func adjusted(for copiedFileMap: CopiedFileMap) -> CallHierarchyItem {
    let adjustedURI = copiedFileMap.adjustedURI(for: uri)
    let adjustedData =
      HierarchyItemData(fromLSPAny: data).map { itemData in
        HierarchyItemData(uri: adjustedURI, usr: itemData.usr).encodeToLSPAny()
      } ?? self.data
    return CallHierarchyItem(
      name: name,
      kind: kind,
      tags: tags,
      detail: detail,
      uri: adjustedURI,
      range: range,
      selectionRange: selectionRange,
      data: adjustedData
    )
  }
}
