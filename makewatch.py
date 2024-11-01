#!/usr/bin/env python3
from __future__ import annotations
"""
A hacky makefile dependency parser to watch the dependencies
of a target and only attempt to rebuild it when they change.
"""
import argparse
import os
import subprocess
import sys

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('target')
    parser.add_argument('--always-make', '-B', action='store_true')
    parser.add_argument('--depsuff', nargs='*', default=['.dep', '.d'], help='suffix for dependency files to be ignore')
    parser.add_argument('--dont-make', '-M', help="Don't build the target first", action='store_true')
    parser.add_argument('--exclude', nargs='*')
    parser.add_argument('--flags', nargs='*')
    args = parser.parse_args()
    run(**vars(args))

def run(target:str, always_make:bool, depsuff:tuple[str, ...], dont_make=False, flags:list[str]=None, exclude:list[str]=None) -> None:
    depsuff = tuple(depsuff)
    if not dont_make:
        subprocess.check_call(['make', target])
    proc = subprocess.Popen(['make', '-p', '--dry-run', target], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    rule = target + ':'
    targets = {}
    excludes = set(exclude) if exclude else set()
    intermediates = set()
    phonies = set()
    assert proc.stdout
    for line_ in proc.stdout:
        line = line_.decode('utf-8').strip()
        if not line:
            continue
        if '=' in line:
            continue
        if '%' in line:
            continue
        if ':' not in line:
            continue
        if 'is up to date' in line:
            continue
        if line.startswith('#'):
            continue
        if line.startswith('.INTERMEDIATE:'):
            intermediates.update(line.split()[1:])
            continue
        if line.startswith('.PHONY:'):
            phonies.update(line.split()[1:])
            continue
        if line.startswith('.'):
            continue
        before, after = line.split(':', 1)
        key = os.path.normpath(before)
        deps = line_to_dependencies(after, depsuff)
        if key in targets:
            targets[key].extend(deps)
        else:
            targets[key] = deps

    proc.wait()
    true_deps = sorted(set(p for p in expand(targets, target)))
    # macwatch can take dependencies via stdin if invoked non-interactively.
    fl = (' -' + ' -'.join(flags)) if flags else ''
    cmd = ['macwatch', f'make {"--always-make " if always_make else ""}{target}{fl}']
    mac = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    try:
        assert mac.stdin
        for dep in true_deps:
            if dep in excludes: continue
            if dep in intermediates: continue
            if dep in phonies: continue
            mac.stdin.write(dep.encode('utf-8')+b'\n')
        mac.stdin.flush()
        mac.stdin.close()
        mac.wait()
    except KeyboardInterrupt:
        mac.kill()

def line_to_dependencies(line:str, depsuff:tuple[str, ...]) -> list[str]:
    '''
    Extracts the dependency list from a target line.
    BUG: files with spaces are incorrectly handled.
    '''
    deps = []
    # ignore order-only dependencies
    idx = line.find('|')
    if idx > -1:
        line = line[:idx]
    for dep in line.strip().split():
        if dep.endswith(depsuff):
            continue
        deps.append(os.path.normpath(dep))
    return deps

def expand(targets:dict[str, list[str]], target:str) -> list[str]:
    '''
    Flattens a dependency graph for a given target to a list.
    As a special case, returns the target itself as a dependency
    if it has no dependencies.
    '''
    deps = targets[target]
    if not deps:
        return [target]
    result = []
    for dep in deps:
        if dep in targets:
            result.extend(expand(targets, dep))
        result.append(dep)
    return result


if __name__ == '__main__':
    main()
