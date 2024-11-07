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

#if compiler(>=6)
import Foundation
package import LanguageServerProtocol
import SwiftExtensions
#else
import Foundation
import LanguageServerProtocol
import SwiftExtensions
#endif

extension DocumentURI {
  /// If this is a file URI pointing to a symlink, return the realpath of the URI, otherwise return `nil`.
  package var symlinkTarget: DocumentURI? {
    guard let fileUrl = fileURL else {
      return nil
    }
    guard let realpath = try? DocumentURI(fileUrl.realpath) else {
      return nil
    }
    if realpath == self {
      return nil
    }
    return realpath
  }
}
