import XCTest

import LSPSupportTests
import LanguageServerProtocolJSONRPCTests
import LanguageServerProtocolTests
import SKCoreTests
import SKSupportTests
import SKSwiftPMWorkspaceTests
import SourceKitTests

var tests = [XCTestCaseEntry]()
tests += LSPSupportTests.__allTests()
tests += LanguageServerProtocolJSONRPCTests.__allTests()
tests += LanguageServerProtocolTests.__allTests()
tests += SKCoreTests.__allTests()
tests += SKSupportTests.__allTests()
tests += SKSwiftPMWorkspaceTests.__allTests()
tests += SourceKitTests.__allTests()

XCTMain(tests)
