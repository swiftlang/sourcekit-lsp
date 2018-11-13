import XCTest

import LanguageServerProtocolJSONRPCTests
import LanguageServerProtocolTests
import SKCoreTests
import SourceKitTests
import SKSupportTests

var tests = [XCTestCaseEntry]()
tests += LanguageServerProtocolJSONRPCTests.__allTests()
tests += LanguageServerProtocolTests.__allTests()
tests += SKCoreTests.__allTests()
tests += SourceKitTests.__allTests()
tests += SKSupportTests.__allTests()

XCTMain(tests)
