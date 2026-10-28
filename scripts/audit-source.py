#!/usr/bin/env python3
"""Fail a source-release check on accidental machine data, credentials, or generated payloads."""
import pathlib, re, subprocess, sys
root = pathlib.Path(__file__).resolve().parent.parent
try:
    paths = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-co', '--exclude-standard', '-z']).decode().split('\0')
except subprocess.CalledProcessError:
    print('Initialize the repository before running the source audit.', file=sys.stderr)
    sys.exit(1)
failures = []
for name in sorted(set(paths)):
    if not name: continue
    path = root / name
    if not path.is_file(): continue
    if name.startswith(('.build/', 'build/', 'dist/', '.backups/')) or path.suffix in ('.p12', '.p8', '.key', '.pem', '.log'):
        failures.append(name + ': generated/private file included')
        continue
    if path.suffix in ('.png', '.icns'): continue
    data = path.read_bytes()
    if len(data) > 1024 * 1024:
        failures.append(name + ': unexpected large source file'); continue
    text = data.decode('utf-8', errors='replace')
    checks = {
        'absolute user home': r'/Users/[A-Za-z0-9_.-]+/',
        'private key': r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        'provider token': r'\b(?:sk-[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{30,})\b',
        'AWS credential': r'\bAKIA[A-Z0-9]{16}\b',
    }
    for label, pattern in checks.items():
        if re.search(pattern, text): failures.append(name + ': ' + label)
if failures:
    print('\n'.join(failures), file=sys.stderr); sys.exit(1)
print(f'Source audit passed ({len(set(paths)) - 1} files). No generated/private payloads detected by the checked patterns.')
