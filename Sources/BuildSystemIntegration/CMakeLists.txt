
add_library(BuildSystemIntegration STATIC
  BuildSettingsLogger.swift
  BuildSystemHooks.swift
  BuildSystemManager.swift
  BuildSystemManagerDelegate.swift
  BuildSystemMessageDependencyTracker.swift
  BuildTargetIdentifierExtensions.swift
  BuiltInBuildSystem.swift
  BuiltInBuildSystemAdapter.swift
  CompilationDatabase.swift
  CompilerCommandLineOption.swift
  DetermineBuildSystem.swift
  ExternalBuildSystemAdapter.swift
  FallbackBuildSettings.swift
  FileBuildSettings.swift
  FixedCompilationDatabaseBuildSystem.swift
  JSONCompilationDatabaseBuildSystem.swift
  LegacyBuildServerBuildSystem.swift
  MainFilesProvider.swift
  SplitShellCommand.swift
  SwiftPMBuildSystem.swift)
set_target_properties(BuildSystemIntegration PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
target_link_libraries(BuildSystemIntegration PUBLIC
  BuildServerProtocol
  LanguageServerProtocol
  LanguageServerProtocolJSONRPC
  SKLogging
  SKOptions
  LanguageServerProtocolExtensions
  SourceKitD
  SwiftExtensions
  ToolchainRegistry
  PackageModel
  TSCBasic
  Build
  SourceKitLSPAPI)

target_link_libraries(BuildSystemIntegration PRIVATE
  SKUtilities
  TSCExtensions)
