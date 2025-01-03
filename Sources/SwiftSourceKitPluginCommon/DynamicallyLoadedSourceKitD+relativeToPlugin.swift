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

import Foundation
import SKLogging
import SwiftExtensions

#if compiler(>=6)
package import SourceKitD
#else
import SourceKitD
#endif

extension DynamicallyLoadedSourceKitD {
  package static let relativeToPlugin: SourceKitD = {
    var dlInfo = Dl_info()
    dladdr(#dsohandle, &dlInfo)
    let path = String(cString: dlInfo.dli_fname)
    var url = URL(fileURLWithPath: path, isDirectory: false)
    while url.pathExtension != "framework" && url.lastPathComponent != "/" {
      url.deleteLastPathComponent()
    }
    url =
      url
      .deletingLastPathComponent()
      .appendingPathComponent("sourcekitd.framework")
      .appendingPathComponent("sourcekitd")

    let dlhandle: DLHandle
    do {
      dlhandle = try dlopen(url.filePath, mode: [.local, .first])
    } catch {
      Logger(subsystem: "org.swift.sourcekit.client-plugin", category: "Loading")
        .error("failed to find sourcekitd.framework relative to \(path); falling back to RTLD_DEFAULT")
      dlhandle = .rtldDefault
    }

    do {
      return try DynamicallyLoadedSourceKitD(
        dlhandle: dlhandle,
        path: URL(string: "fake://")!,
        pluginPaths: nil,
        initialize: false
      )
    } catch {
      fatalError("Failed to load sourcekitd: \(error)")
    }
  }()
}
