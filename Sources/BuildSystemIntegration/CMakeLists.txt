
add_library(BuildSystemIntegration STATIC
  BuildSettingsLogger.swift
  BuildSystemManager.swift
  BuildSystemManagerDelegate.swift
  BuildSystemMessageDependencyTracker.swift
  BuildSystemTestHooks.swift
  BuildTargetIdentifierExtensions.swift
  BuiltInBuildSystem.swift
  BuiltInBuildSystemAdapter.swift
  CompilationDatabase.swift
  CompilationDatabaseBuildSystem.swift
  DetermineBuildSystem.swift
  ExternalBuildSystemAdapter.swift
  FallbackBuildSettings.swift
  FileBuildSettings.swift
  LegacyBuildServerBuildSystem.swift
  MainFilesProvider.swift
  PathPrefixMapping.swift
  PrefixMessageWithTaskEmoji.swift
  SplitShellCommand.swift
  SwiftPMBuildSystem.swift
  TestBuildSystem.swift)
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
