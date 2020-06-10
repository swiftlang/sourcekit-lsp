if(CMAKE_VERSION VERSION_LESS 3.16)
  if(CMAKE_SYSTEM_NAME STREQUAL Windows)
    set(CMAKE_LINK_LIBRARY_FLAG "-l")
    set(CMAKE_LINK_LIBRARY_SUFFIX "")
  endif()
endif()

add_executable(sourcekit-lsp
  main.swift)
target_link_libraries(sourcekit-lsp PRIVATE
  LanguageServerProtocolJSONRPC
  SourceKitLSP
  TSCUtility)
if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
  target_link_libraries(sourcekit-lsp PRIVATE
    FoundationXML)
endif()

install(TARGETS sourcekit-lsp
  DESTINATION bin)
