#!/usr/bin/env python3
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

import argparse
from pathlib import Path
import subprocess

_DESCRIPTION = """
Generate the Sources/SourceKitD/sourcekit_uids.swift from UIDs.py in the main Swift
repository.
Requires swift to be checked out next to the stress tester like this:
  workspace/
    swift/
    sourcekit-lsp/
"""

def parse_args():
  """
  Only used to display the help message for now/
  """
  parser = argparse.ArgumentParser(
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description=_DESCRIPTION
  )

  return parser.parse_args()

def generate_uids_file():
  package_dir = Path(__file__).parent.parent
  workspace_dir = package_dir.parent
  swift_dir = workspace_dir / "swift"
  gyb_exec = swift_dir / "utils" / "gyb"


  swift_source_kit_sources_dir = package_dir / "Sources" / "SourceKitD"

  subprocess.call([
    gyb_exec,
    swift_source_kit_sources_dir / "sourcekitd_uids.swift.gyb",
    "--line-directive=",
    "-o", swift_source_kit_sources_dir / "sourcekitd_uids.swift",
  ])

def main():
  args = parse_args()
  generate_uids_file()


if __name__ == "__main__":
  main()
