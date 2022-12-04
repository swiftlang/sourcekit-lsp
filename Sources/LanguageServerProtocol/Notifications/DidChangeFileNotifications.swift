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

public struct DidCreateFilesNotification: NotificationType {
  public static var method: String = "workspace/didCreateFiles"

  /// An array of all files/folders created in this operation.
  public var files: [FileCreate]

  public init(files: [FileCreate]) {
    self.files = files
  }
}

public struct DidRenameFilesNotification: NotificationType {
  public static var method: String = "workspace/didRenameFiles"

  /// An array of all files/folders renamed in this operation. When a folder
  /// is renamed, only the folder will be included, and not its children.
  public var files: [FileRename]

  public init(files: [FileRename]) {
    self.files = files
  }
}

public struct DidDeleteFilesNotification: NotificationType {
  public static var method: String = "workspace/didDeleteFiles"

  /// An array of all files/folders created in this operation.
  public var files: [FileDelete]

  public init(files: [FileDelete]) {
    self.files = files
  }
}
