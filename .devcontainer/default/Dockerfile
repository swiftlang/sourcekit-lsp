##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

FROM swiftlang/swift:nightly-main-jammy

RUN \
  # Disable apt interactive prompts for this RUN command
  export DEBIAN_FRONTEND="noninteractive" && \
  # Update apt package list
  apt-get update && \
  # Install sourcekit-lsp dependencies
  apt-get install -y libsqlite3-dev libncurses5-dev python3

