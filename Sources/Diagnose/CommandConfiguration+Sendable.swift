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

import ArgumentParser

// If `CommandConfiguration` is not sendable, commands can't have static `configuration` properties.
// Needed until we update Swift CI to swift-argument-parser 1.3.1, which has this conformance (rdar://128042447).
extension CommandConfiguration: @unchecked @retroactive Sendable {}
