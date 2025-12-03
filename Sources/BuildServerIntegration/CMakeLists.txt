
add_library(BuildServerIntegration STATIC
  BuildServerHooks.swift
  BuildServerManager.swift
  BuildServerManagerDelegate.swift
  BuildServerMessageDependencyTracker.swift
  BuildSettingsLogger.swift
  BuildTargetIdentifierExtensions.swift
  BuiltInBuildServer.swift
  BuiltInBuildServerAdapter.swift
  CMakeLists.txt
  CompilationDatabase.swift
  CompilerCommandLineOption.swift
  DetermineBuildServer.swift
  ExternalBuildServerAdapter.swift
  FallbackBuildSettings.swift
  FileBuildSettings.swift
  FixedCompilationDatabaseBuildServer.swift
  JSONCompilationDatabaseBuildServer.swift
  LegacyBuildServer.swift
  MainFilesProvider.swift
  SplitShellCommand.swift
  SwiftPMBuildServer.swift
  SwiftToolchainResolver.swift)
set_target_properties(BuildServerIntegration PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(BuildServerIntegration PUBLIC
  SwiftToolsProtocols::BuildServerProtocol
  SwiftToolsProtocols::LanguageServerProtocol
  SwiftToolsProtocols::LanguageServerProtocolTransport
  SwiftToolsProtocols::SKLogging
  SKOptions
  LanguageServerProtocolExtensions
  SourceKitD
  SwiftExtensions
  SwiftToolsProtocols::ToolsProtocolsSwiftExtensions
  ToolchainRegistry
  PackageModel
  TSCBasic
  Build
  SourceKitLSPAPI
  SwiftASN1)

target_link_libraries(BuildServerIntegration PRIVATE
  SKUtilities
  TSCExtensions)
