#!/usr/bin/env python3
"""Read-only scoped-help validation; no runtime actions are executed."""
import os
import re
import shutil
import subprocess
from pathlib import Path

cli = os.environ.get('HARBOR_CONTAINER') or shutil.which('container')
if not cli:
    raise SystemExit('Install Apple Container or set HARBOR_CONTAINER.')
plugin = os.environ.get('HARBOR_K8S_PLUGIN')
source = (Path(__file__).resolve().parents[1] / 'Sources/HarborCore/Native.swift').read_text()
commands = re.findall(r'\.init\("[^"]+", "[^"]+", "([^"]+)"', source)
failures = []
for command in commands:
    path = command.split()
    executable = cli
    if plugin and path[0] == 'k8s':
        executable = plugin
        path = path[1:]
    result = subprocess.run([executable, *path, '--help'], capture_output=True, text=True, timeout=15)
    scopes = ['USAGE: container ' + command]
    if command.startswith('k8s '):
        scopes.append('USAGE: ' + command)
    if result.returncode or not any(scope in result.stdout for scope in scopes):
        failures.append(command)
        print('FAIL:', command, result.stderr[:180])
print(f'{len(commands) - len(failures)}/{len(commands)} scoped native command help checks passed')
if failures:
    raise SystemExit('Unavailable commands: ' + ', '.join(failures))
