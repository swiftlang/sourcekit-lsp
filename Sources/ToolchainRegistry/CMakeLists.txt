
add_library(ToolchainRegistry STATIC
  Toolchain.swift
  ToolchainRegistry.swift
  XCToolchainPlist.swift)
set_target_properties(ToolchainRegistry PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(ToolchainRegistry PUBLIC
LanguageServerProtocolExtensions
  SKLogging
  SwiftExtensions
  PackageModel
  TSCBasic)

target_link_libraries(ToolchainRegistry PRIVATE
  SKUtilities
  TSCExtensions)
