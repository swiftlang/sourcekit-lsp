add_library(Diagnose STATIC
  CommandLineArgumentsReducer.swift
  DiagnoseCommand.swift
  OSLogScraper.swift
  ReductionError.swift
  ReproducerBundle.swift
  RequestInfo.swift
  SourceKitD+RunWithYaml.swift
  SourceKitDRequestExecutor.swift
  SourcekitdRequestCommand.swift
  SourceReducer.swift)

set_target_properties(Diagnose PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

target_link_libraries(Diagnose PUBLIC
  SKCore
  SourceKitD
  ArgumentParser
  SwiftSyntax::SwiftIDEUtils
  SwiftSyntax::SwiftSyntax
  SwiftSyntax::SwiftParser
  TSCBasic
)
