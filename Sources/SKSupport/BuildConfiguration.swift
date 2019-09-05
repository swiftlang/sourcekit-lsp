//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCUtility

public enum BuildConfiguration: String {
  case debug
  case release
}

extension BuildConfiguration: StringEnumArgument {
  /// Type of shell completion to provide for this argument.
  public static var completion: ShellCompletion {
    return ShellCompletion.none
  }
}
