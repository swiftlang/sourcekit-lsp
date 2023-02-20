#!/usr/bin/env python3

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from typing import Dict, List


# -----------------------------------------------------------------------------
# General utilities


def fatal_error(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def escapeCmdArg(arg: str) -> str:
    if '"' in arg or " " in arg:
        return '"%s"' % arg.replace('"', '\\"')
    else:
        return arg


def print_cmd(cmd: List[str], additional_env: Dict[str, str]) -> None:
    env_str = " ".join([f"{key}={escapeCmdArg(str(value))}" for (key, value) in additional_env.items()])
    command_str = " ".join([escapeCmdArg(str(arg)) for arg in cmd])
    print(f"{env_str} {command_str}")


def env_with_additional_env(additional_env: Dict[str, str]) -> Dict[str, str]:
    env = dict(os.environ)
    for (key, value) in additional_env.items():
        env[key] = str(value)
    return env


def check_call(cmd: List[str], additional_env: Dict[str, str] = {}, verbose: bool = False) -> None:
    if verbose:
        print_cmd(cmd=cmd, additional_env=additional_env)

    subprocess.check_call(cmd, env=env_with_additional_env(additional_env), stderr=subprocess.STDOUT)


def check_output(cmd: List[str], additional_env: Dict[str, str] = {}, capture_stderr: bool = True, verbose: bool = False) -> str:
    if verbose:
        print_cmd(cmd=cmd, additional_env=additional_env)
    if capture_stderr:
        stderr = subprocess.STDOUT
    else:
        stderr = subprocess.DEVNULL
    return subprocess.check_output(cmd, env=env_with_additional_env(additional_env), stderr=stderr, encoding='utf-8')

# -----------------------------------------------------------------------------
# SwiftPM wrappers


def swiftpm_bin_path(swift_exec: str, swiftpm_args: List[str], additional_env: Dict[str, str], verbose: bool = False) -> str:
    """
    Return the path of the directory that contains the binaries produced by this package.
    """
    cmd = [swift_exec, 'build', '--show-bin-path'] + swiftpm_args
    return check_output(cmd, additional_env=additional_env, capture_stderr=False, verbose=verbose).strip()


def get_build_target(swift_exec: str, args: argparse.Namespace) -> str:
    """Returns the target-triple of the current machine or for cross-compilation."""
    try:
        command = [swift_exec, '-print-target-info']
        target_info_json = subprocess.check_output(command, stderr=subprocess.PIPE, universal_newlines=True).strip()
        args.target_info = json.loads(target_info_json)
        if platform.system() == 'Darwin':
            return args.target_info["target"]["unversionedTriple"]
        return args.target_info["target"]["triple"]
    except Exception as e:
        # Temporary fallback for Darwin.
        if platform.system() == 'Darwin':
            return 'x86_64-apple-macosx'
        else:
            fatal_error(str(e))

# -----------------------------------------------------------------------------
# Build SourceKit-LSP


def get_swiftpm_options(swift_exec: str, args: argparse.Namespace) -> List[str]:
    swiftpm_args = [
        '--package-path', args.package_path,
        '--scratch-path', args.build_path,
        '--configuration', args.configuration,
    ]

    if args.multiroot_data_file:
        swiftpm_args += ['--multiroot-data-file', args.multiroot_data_file]

    if args.verbose:
        swiftpm_args += ['--verbose']

    if args.sanitize:
        for san in args.sanitize:
            swiftpm_args += ['--sanitize=%s' % san]

    if platform.system() == 'Darwin':
        swiftpm_args += [
            '-Xlinker', '-rpath', '-Xlinker', '/usr/lib/swift',
            '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../lib/swift/macosx',
            '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../lib/swift-5.5/macosx',
        ]
    else:
        swiftpm_args += [
            # Dispatch headers
            '-Xcxx', '-I', '-Xcxx',
            os.path.join(args.toolchain, 'lib', 'swift'),
            # For <Block.h>
            '-Xcxx', '-I', '-Xcxx',
            os.path.join(args.toolchain, 'lib', 'swift', 'Block'),
        ]

    if 'ANDROID_DATA' in os.environ or (args.cross_compile_host and re.match(
            'android-', args.cross_compile_host)):
        swiftpm_args += [
            '-Xlinker', '-rpath', '-Xlinker', '$ORIGIN/../lib/swift/android',
            # SwiftPM will otherwise try to compile against GNU strerror_r on
            # Android and fail.
            '-Xswiftc', '-Xcc', '-Xswiftc', '-U_GNU_SOURCE',
        ]
    elif platform.system() == 'Linux':
        # Library rpath for swift, dispatch, Foundation, etc. when installing
        swiftpm_args += [
            '-Xlinker', '-rpath', '-Xlinker', '$ORIGIN/../lib/swift/linux',
        ]

    build_target = get_build_target(swift_exec, args)
    if args.cross_compile_host:
        if re.search('-apple-macosx', build_target) and re.match('macosx-', args.cross_compile_host):
            swiftpm_args += ["--arch", "x86_64", "--arch", "arm64"]
        elif re.match('android-', args.cross_compile_host):
            print('Cross-compiling for %s' % args.cross_compile_host)
            swiftpm_args += ['--destination', args.cross_compile_config]
        else:
            fatal_error("cannot cross-compile for %s" % args.cross_compile_host)

    return swiftpm_args


def get_swiftpm_environment_variables(swift_exec: str, args: argparse.Namespace) -> Dict[str, str]:
    """
    Return the environment variables that should be used for a 'swift build' or
    'swift test' invocation.
    """

    env = {
        # Set the toolchain used in tests at runtime
        'SOURCEKIT_TOOLCHAIN_PATH': args.toolchain,
        'INDEXSTOREDB_TOOLCHAIN_BIN_PATH': args.toolchain,
        'SWIFT_EXEC': f'{swift_exec}c'
    }
    # Use local dependencies (i.e. checked out next sourcekit-lsp).
    if not args.no_local_deps:
        env['SWIFTCI_USE_LOCAL_DEPS'] = "1"

    if args.ninja_bin:
        env['NINJA_BIN'] = args.ninja_bin

    if args.sanitize and 'address' in args.sanitize:
        # Workaround reports in Foundation: https://bugs.swift.org/browse/SR-12551
        env['ASAN_OPTIONS'] = 'detect_leaks=false'
    if args.sanitize and 'undefined' in args.sanitize:
        supp = os.path.join(args.package_path, 'Utilities', 'ubsan_supressions.supp')
        env['UBSAN_OPTIONS'] = 'halt_on_error=true,suppressions=%s' % supp
    if args.sanitize and 'thread' in args.sanitize:
        env['TSAN_OPTIONS'] = 'halt_on_error=true'

    if args.action == 'test' and not args.skip_long_tests:
        env['SOURCEKIT_LSP_ENABLE_LONG_TESTS'] = '1'

    return env


def build_single_product(product: str, swift_exec: str, args: argparse.Namespace) -> None:
    """
    Build one product in the package
    """
    swiftpm_args = get_swiftpm_options(swift_exec, args)
    additional_env = get_swiftpm_environment_variables(swift_exec, args)
    if args.action == 'install':
      additional_env['SOURCEKIT_LSP_CI_INSTALL'] = "1"
    cmd = [swift_exec, 'build', '--product', product] + swiftpm_args
    check_call(cmd, additional_env=additional_env, verbose=args.verbose)


def run_tests(swift_exec: str, args: argparse.Namespace) -> None:
    """
    Run all tests in the package
    """
    swiftpm_args = get_swiftpm_options(swift_exec, args)
    additional_env = get_swiftpm_environment_variables(swift_exec, args)

    bin_path = swiftpm_bin_path(swift_exec, swiftpm_args, additional_env=additional_env)
    tests = os.path.join(bin_path, 'sk-tests')
    print('Cleaning ' + tests)
    shutil.rmtree(tests, ignore_errors=True)

    cmd = [
        swift_exec, 'test',
        '--parallel',
        '--disable-testable-imports',
        '--test-product', 'SourceKitLSPPackageTests'
    ] + swiftpm_args
    check_call(cmd, additional_env=additional_env, verbose=args.verbose)


def install_binary(exe: str, source_dir: str, install_dir: str, verbose: bool) -> None:
    cmd = ['rsync', '-a', os.path.join(source_dir, exe), install_dir]
    check_call(cmd, verbose=verbose)


def install(swift_exec: str, args: argparse.Namespace) -> None:
    build_single_product('sourcekit-lsp', swift_exec, args)

    swiftpm_args = get_swiftpm_options(swift_exec, args)
    additional_env = get_swiftpm_environment_variables(swift_exec, args)
    bin_path = swiftpm_bin_path(swift_exec, swiftpm_args=swiftpm_args, additional_env=additional_env)
    
    for prefix in args.install_prefixes:
        install_binary('sourcekit-lsp', bin_path, os.path.join(prefix, 'bin'), verbose=args.verbose)


def handle_invocation(swift_exec: str, args: argparse.Namespace) -> None:
    """
    Depending on the action in 'args', build the package, installs the package or run tests.
    """
    if args.action == 'build':
        # These products are listed in dependency order. Lower-level targets are listed first.
        products = ["LSPBindings", "_SourceKitLSP", "sourcekit-lsp"]
        # Build in reverse dependency order so we can build lower-level targets in parallel.
        for product in reversed(products):
            build_single_product(product, swift_exec, args)
    elif args.action == 'test':
        run_tests(swift_exec, args)
    elif args.action == 'install':
        install(swift_exec, args)
    else:
        fatal_error(f"unknown action '{args.action}'")

# -----------------------------------------------------------------------------
# Argument parsing


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Build along with the Swift build-script.')

    def add_common_args(parser: argparse.ArgumentParser) -> None:
        parser.add_argument('--package-path', metavar='PATH', help='directory of the package to build', default='.')
        parser.add_argument('--toolchain', required=True, metavar='PATH', help='build using the toolchain at PATH')
        parser.add_argument('--ninja-bin', metavar='PATH', help='ninja binary to use for testing')
        parser.add_argument('--build-path', metavar='PATH', default='.build', help='build in the given path')
        parser.add_argument('--configuration', '-c', default='debug', help='build using configuration (release|debug)')
        parser.add_argument('--no-local-deps', action='store_true', help='use normal remote dependencies when building')
        parser.add_argument('--sanitize', action='append', help='build using the given sanitizer(s) (address|thread|undefined)')
        parser.add_argument('--sanitize-all', action='store_true', help='build using every available sanitizer in sub-directories of build path')
        parser.add_argument('--no-clean', action='store_true', help='Don\'t clean the build directory prior to performing the action')
        parser.add_argument('--verbose', '-v', action='store_true', help='enable verbose output')
        parser.add_argument('--cross-compile-host', help='cross-compile for another host instead')
        parser.add_argument('--cross-compile-config', help='an SPM JSON destination file containing Swift cross-compilation flags')
        parser.add_argument('--multiroot-data-file', help='path to an Xcode workspace to create a unified build of all of Swift\'s SwiftPM projects')

    if sys.version_info >= (3, 7, 0):
        subparsers = parser.add_subparsers(title='subcommands', dest='action', required=True, metavar='action')
    else:
        subparsers = parser.add_subparsers(title='subcommands', dest='action', metavar='action')

    build_parser = subparsers.add_parser('build', help='build the package')
    add_common_args(build_parser)

    test_parser = subparsers.add_parser('test', help='test the package')
    add_common_args(test_parser)
    test_parser.add_argument('--skip-long-tests', action='store_true', help='skip run long-running tests')

    install_parser = subparsers.add_parser('install', help='build the package')
    add_common_args(install_parser)
    install_parser.add_argument('--prefix', dest='install_prefixes', nargs='*', metavar='PATHS', help="paths to install sourcekit-lsp, default: 'toolchain/bin'")

    args = parser.parse_args(sys.argv[1:])

    if args.sanitize and args.sanitize_all:
        fatal_error('cannot combine --sanitize with --sanitize-all')

    # Canonicalize paths
    args.package_path = os.path.abspath(args.package_path)
    args.build_path = os.path.abspath(args.build_path)
    args.toolchain = os.path.abspath(args.toolchain)

    if args.action == 'install':
        if not args.install_prefixes:
            args.install_prefixes = [args.toolchain]

    return args


def main() -> None:
    args = parse_args()

    if args.toolchain:
        swift_exec = os.path.join(args.toolchain, 'bin', 'swift')
    else:
        swift_exec = 'swift'

    handle_invocation(swift_exec, args)

    if args.sanitize_all:
        base = args.build_path

        print('=== %s sourcekit-lsp with asan ===' % args.action)
        args.sanitize = ['address']
        args.build_path = os.path.join(base, 'test-asan')
        handle_invocation(swift_exec, args)

        print('=== %s sourcekit-lsp with tsan ===' % args.action)
        args.sanitize = ['thread']
        args.build_path = os.path.join(base, 'test-tsan')
        handle_invocation(swift_exec, args)

        # Linux ubsan disabled: https://bugs.swift.org/browse/SR-12550
        if platform.system() != 'Linux':
            print('=== %s sourcekit-lsp with ubsan ===' % args.action)
            args.sanitize = ['undefined']
            args.build_path = os.path.join(base, 'test-ubsan')
            handle_invocation(swift_exec, args)


if __name__ == '__main__':
    main()
