//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftExtensions
import SwiftIfConfig
import SwiftSyntax

/// A BuildConfiguration implementation for SourceKit-LSP that uses compiler arguments
/// to determine which #if clauses are active.
///
/// This configuration extracts compiler-defined symbols (via -D flags) and platform
/// availability from the compiler arguments to evaluate conditional compilation blocks.
package struct SourceKitLSPBuildConfiguration: BuildConfiguration {
  private let defines: Set<String>
  private let targetTriple: String

  /// Initializes a build configuration from compiler arguments.
  ///
  /// - Parameter compilerArgs: The compiler arguments, typically from a build system.
  package init(compilerArgs: [String]) {
    var defines = Set<String>()
    var targetTriple = ""

    var i = 0
    while i < compilerArgs.count {
      let arg = compilerArgs[i]

      // Extract -D defines
      if arg == "-D" && i + 1 < compilerArgs.count {
        defines.insert(compilerArgs[i + 1])
        i += 2
        continue
      } else if arg.hasPrefix("-D") {
        let define = String(arg.dropFirst(2))
        if !define.isEmpty {
          defines.insert(define)
        }
      }

      // Extract target triple from -target flag
      if arg == "-target" && i + 1 < compilerArgs.count {
        targetTriple = compilerArgs[i + 1]
      }

      i += 1
    }

    self.defines = defines
    self.targetTriple = targetTriple
  }

  // MARK: - BuildConfiguration Protocol

  func isCustomConditionSet(name: String) throws -> Bool {
    return defines.contains(name)
  }

  func hasFeature(name: String) throws -> Bool {
    // We don't have feature availability information from compiler arguments
    return false
  }

  func hasAttribute(name: String) throws -> Bool {
    // We don't have attribute availability information from compiler arguments
    return false
  }

  func canImport(importPath: [(TokenSyntax, String)], version: CanImportVersion) throws -> Bool {
    // Extract the module name from the import path
    guard let firstComponent = importPath.first else {
      return false
    }
    let moduleName = firstComponent.1

    // Check if the module is available based on the target
    switch moduleName {
    case "Darwin":
      // Darwin is available on macOS, iOS, tvOS, watchOS
      return targetTriple.contains("darwin") || targetTriple.contains("macosx") || targetTriple.contains("iphoneos")
        || targetTriple.contains("tvos") || targetTriple.contains("watchos")
    case "Glibc":
      // Glibc is available on Linux
      return targetTriple.contains("linux")
    case "WinSDK":
      // WinSDK is available on Windows
      return targetTriple.contains("windows")
    case "CRT":
      // CRT is available on Windows
      return targetTriple.contains("windows")
    default:
      // For other modules, we can't determine availability from just the target triple
      return false
    }
  }

  func isActiveTargetOS(name: String) throws -> Bool {
    let osName = name.lowercased()

    // Detect OS from target triple
    if targetTriple.contains("darwin") || targetTriple.contains("macosx") {
      return osName == "macos" || osName == "darwin"
    } else if targetTriple.contains("linux") {
      return osName == "linux"
    } else if targetTriple.contains("windows") {
      return osName == "windows"
    } else if targetTriple.contains("android") {
      return osName == "android"
    } else if targetTriple.contains("wasi") {
      return osName == "wasi"
    }

    return false
  }

  func isActiveTargetArchitecture(name: String) throws -> Bool {
    // Extract architecture from target triple (e.g., "x86_64-apple-macosx10.15.0")
    let parts = targetTriple.split(separator: "-")
    guard let arch = parts.first else {
      return false
    }

    let archName = String(arch).lowercased()
    let conditionName = name.lowercased()

    return archName == conditionName || archName.hasPrefix(conditionName)
  }

  func isActiveTargetEnvironment(name: String) throws -> Bool {
    // Check for simulator or similar environments in the target triple
    let lowerTriple = targetTriple.lowercased()
    let lowerName = name.lowercased()

    if lowerName == "simulator" {
      return lowerTriple.contains("simulator")
    }

    return false
  }

  func isActiveTargetRuntime(name: String) throws -> Bool {
    // We don't have runtime information readily available from compiler arguments
    return false
  }

  func isActiveTargetPointerAuthentication(name: String) throws -> Bool {
    // We don't have pointer authentication information from compiler arguments
    return false
  }

  func isActiveTargetObjectFormat(name: String) throws -> Bool {
    // Detect object format from target triple
    let lowerTriple = targetTriple.lowercased()
    let lowerName = name.lowercased()

    if lowerName == "elf" {
      return lowerTriple.contains("linux") || lowerTriple.contains("wasi")
    } else if lowerName == "macho" {
      return lowerTriple.contains("darwin") || lowerTriple.contains("macosx")
    } else if lowerName == "coff" {
      return lowerTriple.contains("windows")
    }

    return false
  }

  var targetPointerBitWidth: Int {
    // Extract pointer width from architecture
    if targetTriple.contains("x86_64") || targetTriple.contains("aarch64") || targetTriple.contains("arm64") {
      return 64
    } else if targetTriple.contains("i386") || targetTriple.contains("armv7") {
      return 32
    }
    return 64  // default to 64-bit
  }

  var targetAtomicBitWidths: [Int] {
    // Most platforms support 8, 16, 32, 64
    return [8, 16, 32, 64]
  }

  var endianness: Endianness {
    // Most common architectures are little-endian
    return .little
  }

  var languageVersion: VersionTuple {
    // Default to Swift 5.0 if we can't determine otherwise
    // VersionTuple requires both major and minor version
    return VersionTuple(5, 0, 0)
  }

  var compilerVersion: VersionTuple {
    // Default to Swift 5.0 if we can't determine otherwise
    return VersionTuple(5, 0, 0)
  }
}
