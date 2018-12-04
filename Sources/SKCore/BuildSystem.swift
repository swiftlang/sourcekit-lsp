//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import LanguageServerProtocol

/// Provider of build settings.
public protocol BuildSettingsProvider {

  /// Returns the settings for the given url and language mode, if known.
  func settings(for: URL, language: Language) -> FileBuildSettings?

  // TODO: notifications when settings change.
}
