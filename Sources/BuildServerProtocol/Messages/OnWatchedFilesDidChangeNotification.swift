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

public import LanguageServerProtocol

/// Notification sent from SourceKit-LSP to the build server to indicate that files within the project have been modified.
public typealias OnWatchedFilesDidChangeNotification = LanguageServerProtocol.DidChangeWatchedFilesNotification

extension OnWatchedFilesDidChangeNotification: BSPNotification {}
