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

package struct CompilerCommandLineOption {
  /// Return value of `matches(argument:)`.
  package enum Match {
    /// The `CompilerCommandLineOption` matched the command line argument. The next element in the command line is a
    /// separate argument and should not be removed.
    case removeOption

    /// The `CompilerCommandLineOption` matched the command line argument. The next element in the command line is an
    /// argument to this option and should be removed as well.
    case removeOptionAndNextArgument
  }

  package enum DashSpelling {
    case singleDash
    case doubleDash
  }

  package enum ArgumentStyles {
    /// A command line option where arguments can be passed without a space such as `-MT/file.txt`.
    case noSpace
    /// A command line option where the argument is passed, separated by a space (eg. `--serialize-diagnostics /file.txt`)
    case separatedBySpace
    /// A command line option where the argument is passed after a `=`, eg. `-fbuild-session-file=`.
    case separatedByEqualSign
  }

  /// The name of the option, without any preceeding `-` or `--`.
  private let name: String

  /// Whether the option can be spelled with one or two dashes.
  private let dashSpellings: [DashSpelling]

  /// The ways that arguments can specified after the option. Empty if the option is a flag that doesn't take any
  /// argument.
  private let argumentStyles: [ArgumentStyles]

  package static func flag(_ name: String, _ dashSpellings: [DashSpelling]) -> CompilerCommandLineOption {
    precondition(!dashSpellings.isEmpty)
    return CompilerCommandLineOption(name: name, dashSpellings: dashSpellings, argumentStyles: [])
  }

  package static func option(
    _ name: String,
    _ dashSpellings: [DashSpelling],
    _ argumentStyles: [ArgumentStyles]
  ) -> CompilerCommandLineOption {
    precondition(!dashSpellings.isEmpty)
    precondition(!argumentStyles.isEmpty)
    return CompilerCommandLineOption(name: name, dashSpellings: dashSpellings, argumentStyles: argumentStyles)
  }

  package func matches(argument: String) -> Match? {
    let argumentName: Substring
    if argument.hasPrefix("--") {
      if dashSpellings.contains(.doubleDash) {
        argumentName = argument.dropFirst(2)
      } else {
        return nil
      }
    } else if argument.hasPrefix("-") {
      if dashSpellings.contains(.singleDash) {
        argumentName = argument.dropFirst(1)
      } else {
        return nil
      }
    } else {
      return nil
    }
    guard argumentName.hasPrefix(self.name) else {
      // Fast path in case the argument doesn't match.
      return nil
    }

    // Examples:
    //  - self.name: "emit-module", argument: "-emit-module", then textAfterArgumentName: ""
    //  - self.name: "o", argument: "-o", then textAfterArgumentName: ""
    //  - self.name: "o", argument: "-output-file-map", then textAfterArgumentName: "utput-file-map"
    //  - self.name: "MT", argument: "-MT/path/to/depfile", then textAfterArgumentName: "/path/to/depfile"
    //  - self.name: "fbuild-session-file", argument: "-fbuild-session-file=/path/to/file", then textAfterArgumentName: "=/path/to/file"
    let textAfterArgumentName: Substring = argumentName.dropFirst(self.name.count)

    if argumentStyles.isEmpty {
      if textAfterArgumentName.isEmpty {
        return .removeOption
      }
      // The command line option is a flag but there is text remaining after the argument name. Thus the flag didn't
      // match. Eg. self.name: "o" and argument: "-output-file-map"
      return nil
    }

    for argumentStyle in argumentStyles {
      switch argumentStyle {
      case .noSpace where !textAfterArgumentName.isEmpty:
        return .removeOption
      case .separatedBySpace where textAfterArgumentName.isEmpty:
        return .removeOptionAndNextArgument
      case .separatedByEqualSign where textAfterArgumentName.hasPrefix("="):
        return .removeOption
      default:
        break
      }
    }
    return nil
  }
}

extension Array<CompilerCommandLineOption> {
  func firstMatch(for argument: String) -> CompilerCommandLineOption.Match? {
    for optionToRemove in self {
      if let match = optionToRemove.matches(argument: argument) {
        return match
      }
    }
    return nil
  }
}
