#!/usr/bin/env python3
"""Fake-gh regression for REST success under explicit system Bash and UTF-8.

Reuses the routing fixture. Missing UTF-8 or Bash 3 coverage is reported as SKIP.
Set TMPDIR to control the location of automatically cleaned fixture directories.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile


test_dir = Path(__file__).resolve().parent
script = test_dir.parent / 'scripts' / 'request-copilot-rereview.sh'
bash = Path('/bin/bash')
if not bash.is_file():
    print('SKIP: /bin/bash unavailable; no system Bash coverage')
    raise SystemExit(0)
version = subprocess.check_output([str(bash), '-c', 'printf "%s" "$BASH_VERSION"'], text=True)
print(f'Interpreter: /bin/bash {version}', flush=True)
if not version.startswith('3.'):
    print('SKIP: Bash 3-specific reproduction; system Bash is not version 3')

locales = ['C']
available = subprocess.check_output(['locale', '-a'], text=True).splitlines()
for candidate in ['en_US.UTF-8'] + [name for name in available if 'utf' in name.lower()]:
    if candidate not in available:
        continue
    env = dict(os.environ, LC_ALL=candidate)
    probe = subprocess.run(['locale', 'charmap'], env=env, capture_output=True, text=True)
    chars = subprocess.run([str(bash), '-c', 's="→"; printf "%s" "${#s}"'],
                           env=env, capture_output=True, text=True)
    if (probe.returncode == 0 and not probe.stderr and
            probe.stdout.strip().upper().replace('-', '') == 'UTF8' and
            chars.returncode == 0 and not chars.stderr and chars.stdout == '1'):
        locales.append(candidate)
        print(f'Validated UTF-8 locale: {candidate}', flush=True)
        break
else:
    print('SKIP: no validated UTF-8 locale; running C control only')

failures = 0
with tempfile.TemporaryDirectory(prefix='copilot-rereview-') as tmp:
    root = Path(tmp)
    bin_dir = root / 'bin'
    bin_dir.mkdir()
    (bin_dir / 'gh').symlink_to(test_dir / 'repository-target-test.py')
    (bin_dir / 'sleep').write_text('#!/bin/sh\nexit 0\n')
    (bin_dir / 'sleep').chmod(0o755)
    for locale_name in locales:
        for mode in ('rest', 'fallback', 'recent'):
            state = root / f'{locale_name}-{mode}'
            state.mkdir()
            env = dict(os.environ)
            for key in ('GH_REPO', 'GH_HOST', 'COPILOT_REREVIEW_COOLDOWN_SECONDS'):
                env.pop(key, None)
            env.update(PATH=str(bin_dir) + os.pathsep + env['PATH'],
                       FAKE_STATE=str(state), FAKE_CWD_REPO='example/widgets',
                       FAKE_MODE=mode, LC_ALL=locale_name)
            run = subprocess.run([str(bash), str(script), '42'], env=env, cwd=state,
                                 capture_output=True, text=True, errors='backslashreplace', timeout=10)
            calls = [json.loads(line) for line in (state / 'calls.jsonl').read_text().splitlines()]
            writes = [call for call in calls if call['mutation']]
            posts = [call for call in writes if call['kind'] == 'api']
            comments = [call for call in writes if call['kind'] == 'pr']
            expected = {
                'rest': 'Copilot re-review requested on example/widgets PR #42 '
                        '(via REST; 0→1 review_requested events)\n',
                'fallback': "REST endpoint silently no-op'd (rate-limit/dedup). "
                            'Falling back to @copilot comment.\n'
                            '@copilot comment posted on example/widgets PR #42 for head aaaaaaa\n',
                'recent': 'Recent @copilot re-review request already exists for head aaaaaaa '
                          '(count=1, cooldown=1800s); skipping duplicate comment.\n',
            }[mode]
            expected_posts = 0 if mode == 'recent' else 1
            ok = (run.returncode == 0 and run.stdout == expected and not run.stderr and
                  len(posts) == expected_posts and len(comments) == (mode == 'fallback') and
                  all(call['args'] == ['api', '-X', 'POST',
                                      '/repos/example/widgets/pulls/42/requested_reviewers',
                                      '-f', 'reviewers[]=Copilot'] for call in posts))
            print(f'{"PASS" if ok else "FAIL"} {locale_name}/{mode}: '
                  f'exit={run.returncode} posts={len(posts)} comments={len(comments)}', flush=True)
            if not ok:
                print(f'stdout={run.stdout!r} stderr={run.stderr!r}')
                failures += 1
raise SystemExit(bool(failures))
