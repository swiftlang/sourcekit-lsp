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

  /// Close and release any underlying resources (e.g. IndexStoreDB).
  func close() async
}

extension MainFilesProvider {
  package func close() async {}
}
