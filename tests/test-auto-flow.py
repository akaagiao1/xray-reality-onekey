#!/usr/bin/env python3
import os, pathlib, pty, select, subprocess, tempfile

repo = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as d:
    tmp = pathlib.Path(d)
    bindir = tmp / 'bin'; bindir.mkdir()
    marker = tmp / 'existing'
    script = (repo / 'auto-reality.sh').read_text()
    start = script.index('existing_xray() {')
    end = script.index('\n}', start) + 2
    script = script[:start] + 'existing_xray() { [[ -e "$TEST_DIR/existing" ]]; }' + script[end:]
    (tmp / 'auto.sh').write_text(script)
    for name, body in {
        'uname': 'echo Linux', 'id': 'echo 0',
        'curl': '''while [ "$#" -gt 0 ]; do case "$1" in -o) out="$2"; shift;; http*) url="$1";; esac; shift; done
case "$url" in */scan-neighbors.sh) cp "$TEST_DIR/scan" "$out";; */reality) cp "$TEST_DIR/installer" "$out";; *) echo 192.0.2.1;; esac''',
    }.items():
        p = bindir / name; p.write_text('#!/bin/bash\n' + body + '\n'); p.chmod(0o755)
    (tmp / 'scan').write_text('''while [ "$#" -gt 0 ]; do case "$1" in --recommend-file) shift; echo scanned.example.com > "$1";; esac; shift; done\n''')
    (tmp / 'installer').write_text('''case "$1" in uninstall) echo "$*" >> "$TEST_DIR/actions"; rm -f "$TEST_DIR/existing";; install) echo "install:$REALITY_SNI:${REALITY_MODES:-interactive}" >> "$TEST_DIR/actions";; esac\n''')
    env = dict(os.environ, PATH=str(bindir)+':'+os.environ['PATH'], TEST_DIR=d, REALITY_SCAN_CIDRS='192.0.2.0/23', REALITY_MODES='1,2,3')
    def run(answer=None):
        if answer is None:
            return subprocess.run(['bash', str(tmp/'auto.sh')], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).returncode
        master, slave = pty.openpty()
        p = subprocess.Popen(['bash', str(tmp/'auto.sh')], env=env, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave); os.write(master, (answer+'\n').encode())
        out = b''
        while True:
            try:
                ready, _, _ = select.select([master], [], [], 10)
                if not ready: p.kill(); raise AssertionError('timed out: '+out.decode(errors='replace'))
                chunk = os.read(master, 65536)
                if not chunk: break
                out += chunk
            except OSError: break
        os.close(master); return p.wait()
    def actions(): return (tmp/'actions').read_text() if (tmp/'actions').exists() else ''
    marker.touch()
    assert run('no') != 0 and marker.exists() and not actions(), 'declining must preserve existing Xray'
    assert run() != 0 and marker.exists() and not actions(), 'noninteractive must preserve existing Xray'
    assert run('yes') == 0, 'confirmation should uninstall and reinstall'
    assert actions().splitlines() == ['uninstall --purge', 'install:scanned.example.com:1,2,3'], actions()
print('auto flow tests passed')
