#!/usr/bin/env python3
"""
A hacky makefile dependency parser to watch the dependencies
of a target and only attempt to rebuild it when they change.
"""
import sys
import subprocess
import argparse

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('target')
    parser.add_argument('--always-make', '-B', action='store_true')
    args = parser.parse_args()
    run(**vars(args))

def line_to_dependencies(line):
    deps = []
    line = line[line.index(':')+1:]
    idx = line.find('|')
    if idx > -1:
        line = line[:idx]
    for dep in line.strip().split():
        if dep.endswith('.dep'):
            continue
        deps.append(dep)
    return deps

def expand(targets, target):
    deps = targets[target]
    if not deps:
        return [target]
    result = []
    for dep in deps:
        if dep in targets:
            result.extend(expand(targets, dep))
        result.append(dep)
    return result

def run(target:str, always_make:bool=False) -> None:
    proc = subprocess.Popen(['make', '-p', '--dry-run'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    rule = target + ':'
    targets = {}
    for line_ in proc.stdout:
        line = line_.decode('utf-8').strip()
        if not line:
            continue
        if line.startswith('#'):
            continue
        if ':' in line:
            targets[line[:line.index(':')]] = line_to_dependencies(line)

    proc.wait()
    true_deps = sorted(set(expand(targets, target)))
    mac = subprocess.Popen(['macwatch', f'make {"--always-make " if always_make else ""}{target}'], stdin=subprocess.PIPE)
    try:
        for dep in true_deps:
            mac.stdin.write(dep.encode('utf-8')+b'\n')
        mac.stdin.flush()
        mac.stdin.close()
        mac.wait()
    except KeyboardInterrupt:
        mac.kill()


if __name__ == '__main__':
    main()
