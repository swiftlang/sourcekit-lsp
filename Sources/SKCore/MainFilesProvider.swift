//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

/// A type that can provide the set of main files that include a particular file.
public protocol MainFilesProvider: AnyObject {

  /// Returns the set of main files that contain the given file.
  ///
  /// For example,
  ///
  /// ```
  /// mainFilesContainingFile("foo.cpp") == Set(["foo.cpp"])
  /// mainFilesContainingFile("foo.h") == Set(["foo.cpp", "bar.cpp"])
  /// ```
  func mainFilesContainingFile(_: DocumentURI) -> Set<DocumentURI>
}

/// Delegate that responds to possible main file changes.
public protocol MainFilesDelegate: AnyObject {

  /// The mapping from files to main files (may have) changed.
  func mainFilesChanged()
}
