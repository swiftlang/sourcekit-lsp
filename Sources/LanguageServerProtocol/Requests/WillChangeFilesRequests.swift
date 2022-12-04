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

/// Represents information on a file/folder create.
public struct FileCreate: Codable, Hashable {
  /// A file:// URI for the location of the file/folder being created.
  public var uri: DocumentURI

  public init(uri: DocumentURI) {
    self.uri = uri
  }
}

public struct WillCreateFilesRequest: RequestType {
  public static var method: String = "workspace/willCreateFiles"
  public typealias Response = WorkspaceEdit?

  /// An array of all files/folders created in this operation.
  public var files: [FileCreate]

  public init(files: [FileCreate]) {
    self.files = files
  }
}

/// Represents information on a file/folder rename.
public struct FileRename: Codable, Hashable {

  /// A file:// URI for the original location of the file/folder being renamed.
  public var oldUri: DocumentURI

  /// A file:// URI for the new location of the file/folder being renamed.
  public var newUri: DocumentURI

  public init(oldUri: DocumentURI, newUri: DocumentURI) {
    self.oldUri = oldUri
    self.newUri = newUri
  }
}

public struct WillRenameFilesRequest: RequestType {
  public static var method: String = "workspace/willRenameFiles"
  public typealias Response = WorkspaceEdit?

  /// An array of all files/folders renamed in this operation. When a folder
  /// is renamed, only the folder will be included, and not its children.
  public var files: [FileRename]

  public init(files: [FileRename]) {
    self.files = files
  }
}

/// Represents information on a file/folder delete.
public struct FileDelete: Codable, Hashable {
  /// A file:// URI for the location of the file/folder being deleted.
  public var uri: DocumentURI

  public init(uri: DocumentURI) {
    self.uri = uri
  }
}

public struct WillDeleteFilesRequest: RequestType {
  public static var method: String = "workspace/willDeleteFiles"
  public typealias Response = WorkspaceEdit?

  /// An array of all files/folders deleted in this operation.
  public var files: [FileDelete]

  public init(files: [FileDelete]) {
    self.files = files
  }
}
