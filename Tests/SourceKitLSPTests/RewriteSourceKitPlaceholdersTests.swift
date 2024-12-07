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

import SKTestSupport
@_spi(Testing) import SourceKitLSP
import XCTest

final class RewriteSourceKitPlaceholdersTests: XCTestCase {
  func testClientDoesNotSupportSnippets() {
    let input = "foo(bar: <#T##Int##Int#>)"
    let rewritten = rewriteSourceKitPlaceholders(in: input, clientSupportsSnippets: false)

    XCTAssertEqual(rewritten, "foo(bar: )")
  }

  func testInputWithoutPlaceholders() {
    let input = "foo()"
    let rewritten = rewriteSourceKitPlaceholders(in: input, clientSupportsSnippets: true)

    XCTAssertEqual(rewritten, "foo()")
  }

  func testPlaceholderWithType() {
    let input = "foo(bar: <#T##bar##Int#>)"
    let rewritten = rewriteSourceKitPlaceholders(in: input, clientSupportsSnippets: true)

    XCTAssertEqual(rewritten, "foo(bar: ${1:Int})")
  }

  func testMultiplePlaceholders() {
    let input = "foo(bar: <#T##Int##Int#>, baz: <#T##String##String#>, quux: <#T##String##String#>)"
    let rewritten = rewriteSourceKitPlaceholders(in: input, clientSupportsSnippets: true)

    XCTAssertEqual(rewritten, "foo(bar: ${1:Int}, baz: ${2:String}, quux: ${3:String})")
  }

  func testClosurePlaceholderReturnType() {
    let input = "foo(bar: <#{ <#T##Int##Int#> }#>)"
    let rewritten = rewriteSourceKitPlaceholders(in: input, clientSupportsSnippets: true)

    XCTAssertEqual(rewritten, #"foo(bar: ${1:{ ${2:Int} \}})"#)
  }

  func testClosurePlaceholderArgumentType() {
    let input = "foo(bar: <#{ <#T##Int##Int#> in <#T##Void##Void#> }#>)"
    let rewritten = rewriteSourceKitPlaceholders(in: input, clientSupportsSnippets: true)

    XCTAssertEqual(rewritten, #"foo(bar: ${1:{ ${2:Int} in ${3:Void} \}})"#)
  }

  func testMultipleClosurePlaceholders() {
    let input = "foo(<#{ <#T##Int##Int#> }#>, baz: <#{ <#Int#> in <#T##Bool##Bool#> }#>)"
    let rewritten = rewriteSourceKitPlaceholders(in: input, clientSupportsSnippets: true)

    XCTAssertEqual(rewritten, #"foo(${1:{ ${2:Int} \}}, baz: ${3:{ ${4:Int} in ${5:Bool} \}})"#)
  }
}
