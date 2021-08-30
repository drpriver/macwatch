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
    args = parser.parse_args()
    run(**vars(args))

def run(target:str) -> None:
    proc = subprocess.Popen(['make', '-p', '--dry-run'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    rule = target + ':'
    deps = []
    for line_ in proc.stdout:
        line = line_.decode('utf-8').strip()
        if not line:
            continue
        if line.startswith('#'):
            continue
        if line.startswith(rule):
            idx = line.find('|')
            if idx > -1:
                line = line[:idx]
            for dep in line[len(rule):].strip().split():
                if dep.endswith('.dep'):
                    continue
                deps.append(dep)
    proc.wait()
    mac = subprocess.Popen(['macwatch', f'make {target}'], stdin=subprocess.PIPE)
    try:
        for dep in deps:
            mac.stdin.write(dep.encode('utf-8')+b'\n')
        mac.stdin.flush()
        mac.stdin.close()
        mac.wait()
    except KeyboardInterrupt:
        mac.kill()


if __name__ == '__main__':
    main()
