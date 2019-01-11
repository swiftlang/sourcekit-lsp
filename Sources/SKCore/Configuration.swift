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

import Foundation
import Utility
import PackageModel

public protocol Configuration {
  var build: SKCore.BuildConfiguration { get }
}

public protocol BuildConfiguration {
  var configuration: PackageModel.BuildConfiguration { get }
  var path: String { get }
  var flags: BuildFlags { get }
}
