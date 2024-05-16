FROM swiftlang/swift:nightly-6.0-jammy

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      sqlite3 \
      libsqlite3-dev \
      libncurses5-dev \
      python3      