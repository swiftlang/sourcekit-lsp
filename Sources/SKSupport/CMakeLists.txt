
add_library(SKSupport STATIC
  BuildConfiguration.swift
  ByteString.swift
  FileSystem.swift
  LineTable.swift
  Platform.swift
  Random.swift
  Result.swift
  dlopen.swift)
set_target_properties(SKSupport PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})
