//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SKTestSupport
@_spi(Testing) import SwiftLanguageService
import XCTest

final class ParametersDocumentationExtractorTests: XCTestCase {
  func testParameterOutlineBasic() {
    let comment = """
      This is a function that does something.

      - Parameters:
        - name: The name parameter
        - age: The age parameter

      This is additional documentation.
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(
      parameters,
      [
        "name": "The name parameter",
        "age": "The age parameter",
      ]
    )

    XCTAssertEqual(
      remaining,
      """
      This is a function that does something.

      This is additional documentation.
      """
    )
  }

  func testParameterOutlineWithComplexDescriptions() {
    let comment = """
      Function documentation.

      - Parameters:
        - callback: A closure that is called when the operation completes.
          This can be `nil` if no callback is needed.
        - timeout: The maximum time to wait in seconds.
          Must be greater than 0.

          ```swift
          let value = 5
          ```
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(
      parameters,
      [
        "callback": """
        A closure that is called when the operation completes.
        This can be `nil` if no callback is needed.
        """,
        "timeout": """
        The maximum time to wait in seconds.
        Must be greater than 0.

        ```swift
        let value = 5
        ```
        """,
      ]
    )

    XCTAssertEqual(remaining, "Function documentation.")
  }

  func testParameterOutlineCaseInsensitive() {
    let comment = """
      - PArAmEtERs:
        - value: A test value
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(parameters, ["value": "A test value"])
    XCTAssertTrue(remaining.isEmpty)
  }

  func testSeparatedParametersBasic() {
    let comment = """
      This function does something.

      - Parameter name: The name of the person
      - Parameter age: The age of the person

      Additional documentation.
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(
      parameters,
      [
        "name": "The name of the person",
        "age": "The age of the person",
      ]
    )

    XCTAssertEqual(
      remaining,
      """
      This function does something.

      Additional documentation.
      """
    )
  }

  func testSeparatedParametersCaseInsensitive() {
    let comment = """
      - parameter value: A test value
      - PARAMETER count: A test count
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(
      parameters,
      [
        "value": "A test value",
        "count": "A test count",
      ]
    )

    XCTAssertTrue(remaining.isEmpty)
  }

  func testSeparatedParameterWithComplexDescription() {
    let comment = """
      - Parameter completion: A completion handler that is called when the request finishes.
        The handler receives a `Result` containing either the response data or an error.
        This parameter can be `nil` if no completion handling is needed.
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(
      parameters,
      [
        "completion": """
        A completion handler that is called when the request finishes.
        The handler receives a `Result` containing either the response data or an error.
        This parameter can be `nil` if no completion handling is needed.
        """
      ]
    )

    XCTAssertTrue(remaining.isEmpty)
  }

  func testDoxygenParameterBasic() {
    let comment = #"""
      This function processes data.

      \param input The input data to process
      \param options Configuration options

      \returns The processed result
      """#

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(
      parameters,
      [
        "input": "The input data to process",
        "options": "Configuration options",
      ]
    )

    XCTAssertEqual(
      remaining,
      #"""
      This function processes data.

      \returns The processed result
      """#
    )
  }

  func testMarkdownWithoutParameters() {
    let comment = """
      This is a function that takes no parameters.

      It does something useful and returns a value.

      - Returns: The processed result.
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(parameters, [:])
    XCTAssertEqual(
      remaining,
      """
      This is a function that takes no parameters.

      It does something useful and returns a value.

      - Returns: The processed result.
      """
    )
  }

  func testParameterExtractionDoesNotAffectOtherLists() {
    let comment = """
      This function has various lists:

      - Parameters:
        - name: The user name
      - Returns: The processed result.
      - Throws: An error if the function fails.
      - Precondition: the user is logged in.
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(parameters, ["name": "The user name"])

    XCTAssertEqual(
      remaining,
      """
      This function has various lists:

      - Returns: The processed result.
      - Throws: An error if the function fails.
      - Precondition: the user is logged in.
      """
    )
  }

  /// Tests that we drop non-parameter items in the parameter outline. Aligns with swift-docc.
  func testDropsNonParameterItemsInParameterOutline() {
    let comment = """
      - Parameters:
        - number: The number to do stuff with
        - TODO Improve this documentation
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(parameters, ["number": "The number to do stuff with"])
    XCTAssertTrue(remaining.isEmpty)
  }

  /// Tests that we drop duplicate parameter documentation and keep thefirst one. Aligns with swift-docc.
  func testDropsDuplicateParameterDocumentation() {
    let comment = """
      - Parameters:
        - number: The number to do stuff with
        - number: The number to do amazing stuff with
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(parameters, ["number": "The number to do stuff with"])
    XCTAssertTrue(remaining.isEmpty)
  }

  /// Tests that we drop text after the colon in the parameter outline. Aligns with swift-docc.
  func testDropsTextAfterColonInParameterOutline() {
    let comment = """
      - Parameters: listing parameter documentation below
        - number: The number to do stuff
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(parameters, ["number": "The number to do stuff"])
    XCTAssertTrue(remaining.isEmpty)
  }

  /// Tests that we support mixed parameter documentation styles in a single comment. Aligns with swift-docc.
  func testMixedParameterDocumentationStyles() {
    let comment = #"""
      Function documentation.

      - Parameters:
        - first: First parameter from Parameters section
      - Parameter second: Second parameter from separate Parameter
      \param third Third parameter from Doxygen style

      Additional documentation.
      """#

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(
      parameters,
      [
        "first": "First parameter from Parameters section",
        "second": "Second parameter from separate Parameter",
        "third": "Third parameter from Doxygen style",
      ]
    )

    XCTAssertEqual(
      remaining,
      """
      Function documentation.

      Additional documentation.
      """
    )
  }

  func testSeparatedParameterWithRawIdentifier() {
    let comment = """
      - Parameter `foo: bar :) `: hello
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(parameters, ["foo: bar :) ": "hello"])
    XCTAssertTrue(remaining.isEmpty)
  }

  func testParameterOutlineWithRawIdentifier() {
    let comment = """
      - Parameters:
         - `foo: bar :) `: hello
      """

    let (parameters, remaining) = extractParametersDocumentation(from: comment)

    XCTAssertEqual(parameters, ["foo: bar :) ": "hello"])
    XCTAssertTrue(remaining.isEmpty)
  }
}
