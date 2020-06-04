import XCTest

import LSPLoggingTests
import LanguageServerProtocolJSONRPCTests
import LanguageServerProtocolTests
import SKCoreTests
import SKSupportTests
import SKSwiftPMWorkspaceTests
import SourceKitDTests
import SourceKitLSPTests

var tests = [XCTestCaseEntry]()
tests += LSPLoggingTests.__allTests()
tests += LanguageServerProtocolJSONRPCTests.__allTests()
tests += LanguageServerProtocolTests.__allTests()
tests += SKCoreTests.__allTests()
tests += SKSupportTests.__allTests()
tests += SKSwiftPMWorkspaceTests.__allTests()
tests += SourceKitDTests.__allTests()
tests += SourceKitLSPTests.__allTests()

XCTMain(tests)
