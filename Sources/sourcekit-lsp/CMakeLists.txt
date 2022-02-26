
add_executable(sourcekit-lsp
  main.swift)
target_link_libraries(sourcekit-lsp PRIVATE
  ArgumentParser
  LanguageServerProtocolJSONRPC
  SourceKitLSP
  TSCUtility)
if(NOT CMAKE_SYSTEM_NAME STREQUAL Darwin)
  if(Foundation_FOUND)
    target_link_libraries(sourcekit-lsp PRIVATE
      FoundationXML)
  endif()
endif()

install(TARGETS sourcekit-lsp
  DESTINATION bin)
