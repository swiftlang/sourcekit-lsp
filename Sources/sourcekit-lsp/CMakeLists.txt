if(CMAKE_VERSION VERSION_LESS 3.16)
  if(CMAKE_SYSTEM_NAME STREQUAL Windows)
    set(CMAKE_LINK_LIBRARY_FLAG "-l")
    set(CMAKE_LINK_LIBRARY_SUFFIX "")
  endif()
endif()

add_executable(sourcekit-lsp
  main.swift)
target_link_libraries(sourcekit-lsp PRIVATE
  ArgumentParser
  LanguageServerProtocolJSONRPC
  SourceKitLSP
  TSCUtility)
target_link_libraries(sourcekit-lsp PRIVATE
  $<$<NOT:$<PLATFORM_ID:Darwin>>:FoundationXML>)

install(TARGETS sourcekit-lsp
  DESTINATION bin)
