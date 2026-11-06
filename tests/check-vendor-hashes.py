from pathlib import Path
import hashlib
import re

repo = Path(__file__).resolve().parent.parent
script = (repo / 'scan-neighbors.sh').read_text()
for arch in ('amd64', 'arm64'):
    line = next(x for x in script.splitlines() if x.strip().startswith(arch + ') SCANNER_HASH='))
    for key, path in [('SCANNER_HASH', f'RealiTLScanner-linux-{arch}'), ('CHECKER_HASH', f'reality-checker-linux-{arch}.zip')]:
        match = re.search(rf'{key}=([0-9a-f]+)', line)
        assert match, f'{key} {arch} missing'
        expected = match.group(1)
        actual = hashlib.sha256((repo / 'vendor' / path).read_bytes()).hexdigest()
        assert expected == actual, f'{path} SHA-256 differs: script={expected} actual={actual}'
for name in ('cdn_keywords.txt', 'hot_websites.txt', 'gfwlist.conf', 'Country.mmdb'):
    actual = hashlib.sha256((repo / 'vendor/data' / name).read_bytes()).hexdigest()
    assert f'{name} {actual}' in script, f'{name} SHA-256 differs'
print('All bundled file hashes match script')
