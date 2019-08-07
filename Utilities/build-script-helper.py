#!/usr/bin/env python

from __future__ import print_function

import argparse
import os
import platform
import shutil
import subprocess
import sys

def swiftpm(action, swift_exec, swiftpm_args, env=None):
  cmd = [swift_exec, action] + swiftpm_args
  print(' '.join(cmd))
  subprocess.check_call(cmd, env=env)

def swiftpm_bin_path(swift_exec, swiftpm_args, env=None):
  cmd = [swift_exec, 'build', '--show-bin-path'] + swiftpm_args
  print(' '.join(cmd))
  return subprocess.check_output(cmd, env=env).strip()

def get_swiftpm_options(args):
  swiftpm_args = [
    '--package-path', args.package_path,
    '--build-path', args.build_path,
    '--configuration', args.configuration,
  ]

  if args.verbose:
    swiftpm_args += ['--verbose']

  if args.configuration == 'release':
    # Enable running tests that use @testable in release builds.
    swiftpm_args += ['-Xswiftc', '-enable-testing']

  if platform.system() != 'Darwin':
    swiftpm_args += [
      # Dispatch headers
      '-Xcxx', '-I', '-Xcxx',
      os.path.join(args.toolchain, 'usr', 'lib', 'swift'),
      # For <Block.h>
      '-Xcxx', '-I', '-Xcxx',
      os.path.join(args.toolchain, 'usr', 'lib', 'swift', 'Block'),
    ]

  return swiftpm_args

def main():
  parser = argparse.ArgumentParser(description='Build along with the Swift build-script.')
  def add_common_args(parser):
    parser.add_argument('--package-path', metavar='PATH', help='directory of the package to build', default='.')
    parser.add_argument('--toolchain', required=True, metavar='PATH', help='build using the toolchain at PATH')
    parser.add_argument('--ninja-bin', metavar='PATH', help='ninja binary to use for testing')
    parser.add_argument('--build-path', metavar='PATH', default='.build', help='build in the given path')
    parser.add_argument('--configuration', '-c', default='debug', help='build using configuration (release|debug)')
    parser.add_argument('--verbose', '-v', action='store_true', help='enable verbose output')

  subparsers = parser.add_subparsers(title='subcommands', dest='action', metavar='action')
  build_parser = subparsers.add_parser('build', help='build the package')
  add_common_args(build_parser)

  test_parser = subparsers.add_parser('test', help='test the package')
  add_common_args(test_parser)

  args = parser.parse_args(sys.argv[1:])

  # Canonicalize paths
  args.package_path = os.path.abspath(args.package_path)
  args.build_path = os.path.abspath(args.build_path)
  args.toolchain = os.path.abspath(args.toolchain)

  if args.toolchain:
    swift_exec = os.path.join(args.toolchain, 'usr', 'bin', 'swift')
  else:
    swift_exec = 'swift'

  swiftpm_args = get_swiftpm_options(args)

  env = os.environ
  # Set the toolchain used in tests at runtime
  env['SOURCEKIT_TOOLCHAIN_PATH'] = args.toolchain
  # Use local dependencies (i.e. checked out next sourcekit-lsp).
  env['SWIFTCI_USE_LOCAL_DEPS'] = "1"

  if args.ninja_bin:
    env['NINJA_BIN'] = args.ninja_bin

  if args.action == 'build':
    swiftpm('build', swift_exec, swiftpm_args, env)
  elif args.action == 'test':
    bin_path = swiftpm_bin_path(swift_exec, swiftpm_args, env)
    tests = os.path.join(bin_path, 'sk-tests')
    print('Cleaning ' + tests)
    shutil.rmtree(tests, ignore_errors=True)
    swiftpm('test', swift_exec, swiftpm_args, env)
  else:
    assert False, 'unknown action \'{}\''.format(args.action)

if __name__ == '__main__':
  main()
