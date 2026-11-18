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

import Foundation
@_spi(SourceKitLSP) package import LanguageServerProtocol

/// A type that can provide the set of main files that include a particular file.
package protocol MainFilesProvider: Sendable {
  /// Returns all the files that (transitively) include the header file at the given path.
  ///
  /// If `crossLanguage` is set to `true`, Swift files that import a header through a module will also be reported.
  ///
  /// ### Examples
  ///
  /// ```
  /// mainFilesContainingFile("foo.cpp") == Set(["foo.cpp"])
  /// mainFilesContainingFile("foo.h") == Set(["foo.cpp", "bar.cpp"])
  /// ```
  func mainFiles(containing uri: DocumentURI, crossLanguage: Bool) async -> Set<DocumentURI>

  /// Returns the files that the file at the given URI includes directly.
  ///
  /// ### Examples
  ///
  /// ```
  /// files(includedBy: "foo.cpp") == Set(["foo.h", "bar.h"])
  /// ```
  func files(includedBy uri: DocumentURI) async -> Set<DocumentURI>
}

extension MainFilesProvider {
  package func files(includedBy uri: DocumentURI) async -> Set<DocumentURI> {
    return []
  }
}

/// The lowercased path extensions of C, C++, Objective-C and Objective-C++ source files.
package let cFamilySourceFileExtensions = ["c", "cc", "cp", "cpp", "cxx", "c++", "m", "mm"]

extension DocumentURI {
  /// Whether this is a C, C++, Objective-C or Objective-C++ source file, as opposed to a header or another file that is
  /// only ever included.
  package var isCFamilySourceFile: Bool {
    let pathExtension = (self.pseudoPath as NSString).pathExtension.lowercased()
    return cFamilySourceFileExtensions.contains(pathExtension)
  }
}
