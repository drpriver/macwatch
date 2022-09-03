#!/usr/bin/env python3
"""
A hacky makefile dependency parser to watch the dependencies
of a target and only attempt to rebuild it when they change.
"""
import sys
import subprocess
import argparse
from typing import List, Dict, Tuple, Set

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('target')
    parser.add_argument('--always-make', '-B', action='store_true')
    parser.add_argument('--depsuff', nargs='*', default=['.dep', '.d'], help='suffix for dependency files to be ignore')
    parser.add_argument('--dont-make', '-M', help="Don't build the target first")
    parser.add_argument('--exclude', nargs='*')
    parser.add_argument('--flags', nargs='*')
    args = parser.parse_args()
    run(**vars(args))

def run(target:str, always_make:bool, depsuff:Tuple[str], dont_make=False, flags:List[str]=None, exclude:List[str]=None) -> None:
    depsuff = tuple(depsuff)
    if not dont_make:
        subprocess.check_call(['make', target])
    proc = subprocess.Popen(['make', '-p', '--dry-run', target], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    rule = target + ':'
    targets = {}
    excludes = set(exclude) if exclude else set()
    assert proc.stdout
    for line_ in proc.stdout:
        line = line_.decode('utf-8').strip()
        if not line:
            continue
        if line.startswith('#'):
            continue
        if ':' in line:
            targets[line[:line.index(':')]] = line_to_dependencies(line, depsuff)

    proc.wait()
    true_deps = sorted(set(expand(targets, target)))
    # macwatch can take dependencies via stdin if invoked non-interactively.
    fl = (' -' + ' -'.join(flags)) if flags else ''
    cmd = ['macwatch', f'make {"--always-make " if always_make else ""}{target}{fl}']
    mac = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    try:
        assert mac.stdin
        for dep in true_deps:
            mac.stdin.write(dep.encode('utf-8')+b'\n')
        mac.stdin.flush()
        mac.stdin.close()
        mac.wait()
    except KeyboardInterrupt:
        mac.kill()

def line_to_dependencies(line:str, depsuff:Tuple[str]) -> List[str]:
    '''
    Extracts the dependency list from a target line.
    BUG: files with spaces are incorrectly handled.
    '''
    deps = []
    line = line[line.index(':')+1:]
    # ignore order-only dependencies
    idx = line.find('|')
    if idx > -1:
        line = line[:idx]
    for dep in line.strip().split():
        if dep.endswith(depsuff):
            continue
        deps.append(dep)
    return deps

def expand(targets:Dict[str, List[str]], target:str) -> List[str]:
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
