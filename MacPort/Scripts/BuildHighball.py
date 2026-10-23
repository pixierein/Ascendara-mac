#!/usr/bin/env python3
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

Version = 'v0.10.22'
Commit = 'daa2095b9fd4abad0b9db7c57cacbd4d49a9e06e'
Repository = 'https://github.com/gauthierpiarrette/highball'
Root = Path(__file__).resolve().parents[1]
SourceDirectory = Root / '.build-tools/Highball' / Version
DefaultOutput = Root / 'BuildTools/Highball'


def Run(Arguments, Directory=Root):
    subprocess.run([str(Argument) for Argument in Arguments], cwd=Directory, check=True)


def Preflight():
    Errors = []
    if sys.platform != 'darwin':
        Errors.append('Highball builds on macOS only.')
    for Command in ('git', 'swift', 'lipo'):
        if not shutil.which(Command):
            Errors.append(f'Missing Highball build dependency: {Command} (install Xcode command line tools)')
    return Errors


def Checkout():
    if not (SourceDirectory / '.git').is_dir():
        if SourceDirectory.exists():
            shutil.rmtree(SourceDirectory)
        SourceDirectory.parent.mkdir(parents=True, exist_ok=True)
        Run(['git', 'clone', '--quiet', '--depth', '1', '--branch', Version, Repository, SourceDirectory])
    Head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=SourceDirectory, text=True).strip()
    if Head != Commit:
        raise RuntimeError(f'Highball {Version} resolved to {Head}, expected {Commit}; refusing to build.')


def Build(Output):
    Checkout()
    Run(['swift', 'build', '-c', 'release', '--product', 'highball', '--arch', 'arm64'], Directory=SourceDirectory)
    Binary = SourceDirectory / '.build/arm64-apple-macosx/release/highball'
    if not Binary.is_file():
        Binary = SourceDirectory / '.build/release/highball'
    Run(['lipo', Binary, '-verify_arch', 'arm64'])
    Output = Path(Output)
    if Output.exists():
        shutil.rmtree(Output)
    Output.mkdir(parents=True)
    shutil.copy2(Binary, Output / 'highball')
    (Output / 'highball').chmod(0o755)
    shutil.copy2(SourceDirectory / 'spike/engine-manifest.json', Output / 'engine-manifest.json')
    shutil.copy2(SourceDirectory / 'spike/d3dmetal-license.txt', Output / 'd3dmetal-license.txt')
    shutil.copy2(SourceDirectory / 'LICENSE', Output / 'LICENSE')
    (Output / 'SOURCE.txt').write_text(
        f'Highball {Version} ({Commit})\n'
        f'Licensed under the GNU General Public License v3.0; see LICENSE.\n'
        f'Corresponding source: {Repository}/tree/{Commit}\n')
    return Output


def Main():
    Parser = argparse.ArgumentParser(description='Build the pinned Apple Silicon Highball CLI, engine manifest and notices.')
    Parser.add_argument('--output', dest='Output', default=DefaultOutput, help='Directory to stage the CLI into')
    Arguments = Parser.parse_args()
    Errors = Preflight()
    if Errors:
        print('\n'.join(Errors), file=sys.stderr)
        return 1
    print(f'Highball {Version} staged in {Build(Arguments.Output)}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(Main())
    except (subprocess.CalledProcessError, OSError, RuntimeError) as Error:
        print(f'Highball build failed: {Error}', file=sys.stderr)
        sys.exit(1)
