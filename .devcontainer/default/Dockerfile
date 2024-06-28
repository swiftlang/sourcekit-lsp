FROM swiftlang/swift:nightly-main-jammy

RUN \
  # Disable apt interactive prompts for this RUN command
  export DEBIAN_FRONTEND="noninteractive" && \
  # Update apt package list
  apt-get update && \
  # Install sourcekit-lsp dependencies
  apt-get install -y libsqlite3-dev libncurses5-dev python3

