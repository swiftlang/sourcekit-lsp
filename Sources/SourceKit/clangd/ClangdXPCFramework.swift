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

#if os(macOS)

import Basic
import Foundation

typealias clangd_xpc_get_bundle_identifier_t = @convention(c) () -> UnsafePointer<CChar>

/// A thin wrapper over the `ClangdXPCFramework` which makes the `clangd` XPC
/// service available to the process that loads it.
public struct ClangdXPCFramework {
    let handle: UnsafeMutableRawPointer
    public let xpcBundleIdentifier: String

    public init?(path: AbsolutePath) {
        precondition(path.pathString.contains("ClangdXPC.framework"))
        guard let clangdXPCHandle = path.pathString.withCString ({
            dlopen($0, RTLD_LOCAL | RTLD_FIRST)
        }) else {
            return nil
        }
        guard let symbol = "clangd_xpc_get_bundle_identifier".withCString ({
            dlsym(clangdXPCHandle, $0)
        }) else {
            return nil
        }
        let fn = unsafeBitCast(symbol, to: clangd_xpc_get_bundle_identifier_t.self)
        handle = clangdXPCHandle
        xpcBundleIdentifier = String.init(cString: fn())
    }

    public func unload() {
        dlclose(handle)
    }
}

#endif
