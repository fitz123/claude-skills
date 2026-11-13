#!/usr/bin/env python3
"""Safe repository-routing fixtures. Optional argument: alternate scripts directory.

Every gh invocation is fake. JSONL call logs and helper output are retained in
REPOSITORY_TEST_RESULTS when set, otherwise in a temporary directory.
Repository-routing subprocesses use the same C locale for baseline and changed scripts.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def fake_gh():
    args = sys.argv[1:]
    state = Path(os.environ['FAKE_STATE'])
    explicit = os.environ.get('GH_REPO', '')
    cwd_repo = os.environ.get('FAKE_CWD_REPO', '')
    host = os.environ.get('GH_HOST') or 'github.com'
    repo = cwd_repo
    mutation = False
    kind = args[0]
    if kind == 'repo':
        # Real gh repo view ignores GH_REPO unless supplied positionally.
        if '--' in args:
            positional = args[args.index('--') + 1:]
            repo = positional[0] if positional else cwd_repo
        else:
            # -bob/widgets is parsed as -b with an attached branch value.
            repo = args[2] if len(args) > 2 and not args[2].startswith('-') else cwd_repo
    elif kind == 'pr':
        repo = explicit or cwd_repo
        mutation = args[1] == 'comment'
    elif kind == 'api':
        text = ' '.join(args)
        mutation = '-X POST' in text or 'mutation(' in text
        match = re.search(r'repos/([^/]+/[^/]+)/', text)
        if match:
            repo = match[1]
        elif 'repository(owner:' in text:
            match = re.search(r'owner:"([^"]+)",name:"([^"]+)"', text)
            repo = '/'.join(match.groups()) if match else 'unknown/unknown'
        else:
            # Thread IDs belong to the repository selected by the prior query.
            repo = (state / 'thread-repo').read_text()
    if kind in ('repo', 'pr'):
        # ghrepo accepts SCP syntax and normalizes repo/pr hosts; gh api uses
        # raw GH_HOST. Keep those behaviors distinct to expose mixed targets.
        scp = re.fullmatch(r'git@([^:]+):(.+/.+)', repo)
        if scp:
            host, repo = scp.groups()
        elif repo.count('/') == 2:
            host, repo = repo.split('/', 1)
        host = host.lower().removeprefix('www.')
    with (state / 'calls.jsonl').open('a') as log:
        log.write(json.dumps(dict(kind=kind, args=args, target=f'{host}/{repo}', mutation=mutation)) + '\n')
    if kind == 'repo':
        if not repo or repo == 'missing/widgets':
            return 1
        if repo == 'empty/widgets':
            return 0
        # gh repo view also accepts one-part shorthand, unlike gh pr.
        print(repo if '/' in repo else 'cwd/' + repo)
    elif kind == 'pr':
        if explicit and (explicit.count('/') not in (1, 2) or
                         '' in explicit.split('/') or explicit == 'missing/widgets'):
            return 1
        text = ' '.join(args)
        if args[1] == 'comment':
            (state / 'requested').touch()
        elif args[1] == 'checks':
            print('[{"state":"SUCCESS","completedAt":"2026-01-01T00:00:00Z"}]' if '--json' in args else 'ci pass')
        elif 'headRefName,title' in text:
            print('{"headRefName":"fix/example","title":"Fix example"}')
        elif 'headRefOid' in text:
            print('a' * 40)
        elif 'commits' in text:
            print('2026-01-01T00:00:00Z')
        elif 'comments' in text:
            print('[]' if 'body:' in text else '0')
        else:
            print('[]')
    elif kind == 'api':
        text = ' '.join(args)
        if 'resolveReviewThread' in text:
            print('{}')
        elif 'graphql' in args:
            (state / 'thread-repo').write_text(repo)
            print('THREAD_fixture' if 'select(.isResolved == false) | .id' in text else '[]')
        elif mutation:
            (state / 'requested').touch()
            print('{}')
        elif '/reviews' in text:
            print('1' if (state / 'requested').exists() else '0')
        elif 'requested_reviewers' in text:
            print('0')
        elif '/timeline' in text:
            if '--jq' in args:
                print('1' if os.environ['FAKE_MODE'] == 'rest' and (state / 'requested').exists() else '0')
            else:
                print('[]')
        elif '/comments' in text:
            print(json.dumps([{'body': '<!-- github-pr-rereview-head:' + 'a' * 40 + ' -->',
                               'created_at': '2099-01-01T00:00:00Z'}])
                  if os.environ['FAKE_MODE'] == 'recent' else '[]')
        else:
            raise RuntimeError(args)
    else:
        raise RuntimeError(args)
    return 0


if Path(sys.argv[0]).name == 'gh':
    sys.exit(fake_gh())

scripts = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'scripts').resolve()
results = Path(os.environ.get('REPOSITORY_TEST_RESULTS') or tempfile.mkdtemp(prefix='repository-target-')).resolve()
results.mkdir(parents=True, exist_ok=True)
bin_dir = results / 'bin'
bin_dir.mkdir(exist_ok=True)
(bin_dir / 'gh').symlink_to(Path(__file__).resolve())
(bin_dir / 'sleep').write_text('#!/bin/sh\nexit 0\n')
(bin_dir / 'sleep').chmod(0o755)
cases = [
    ('explicit', 'selected/widgets', 'cwd/project', False, ''),
    ('outside', 'selected/widgets', '', False, ''),
    ('unset', None, 'cwd/project', False, ''),
    ('empty', '', 'cwd/project', False, ''),
    ('missing', 'missing/widgets', 'cwd/project', True, ''),
    ('one-part', 'widgets', 'cwd/project', True, ''),
    ('empty-segment', 'selected//widgets', 'cwd/project', True, ''),
    ('empty-result', 'empty/widgets', 'cwd/project', True, ''),
    ('host-default', 'github.com/selected/widgets', 'cwd/project', False, ''),
    ('host-explicit', 'git.example/selected/widgets', 'cwd/project', False, ''),
    ('host-conflict', 'git.example/selected/widgets', 'cwd/project', False, 'other.example'),
]
# Additional contexts are reported separately from the original 44-case A/B.
regression_cases = [
    ('www-host', 'www.GitHub.COM/selected/widgets', 'cwd/project', False, ''),
    ('uppercase-www-host', 'WWW.GitHub.COM/selected/widgets', 'cwd/project', False, ''),
    ('option-selector', '-bob/widgets', 'cwd/project', True, ''),
    ('ssh-selector', 'git@ghe.example:selected/widgets', 'cwd/project', True, ''),
]
helpers = [('poll', 'poll-pr-review.sh', 'fallback'),
           ('request-rest', 'request-copilot-rereview.sh', 'rest'),
           ('request-fallback', 'request-copilot-rereview.sh', 'fallback'),
           ('resolve', 'resolve-all-threads.sh', 'fallback')]
failed = wrong_total = wrong_writes_total = 0
groups = {'ORIGINAL': [0, 0, 0, 0], 'REGRESSIONS': [0, 0, 0, 0]}
for helper, script, mode in helpers:
    for label, explicit, cwd_repo, invalid, gh_host in cases + regression_cases:
        state = results / f'{helper}-{label}'
        state.mkdir()
        env = dict(os.environ)
        for key in ('GH_REPO', 'GH_HOST', 'GH_PR_NOTIFY_TARGET', 'GH_PR_REQUEST_SCRIPT', 'GH_PR_ALLOW_NO_CHECKS'):
            env.pop(key, None)
        env.update(PATH=str(bin_dir) + os.pathsep + env['PATH'], FAKE_STATE=str(state),
                   FAKE_CWD_REPO=cwd_repo, FAKE_MODE=mode, LC_ALL='C')
        if explicit is not None:
            env['GH_REPO'] = explicit
        if gh_host:
            env['GH_HOST'] = gh_host
        intended = explicit or cwd_repo
        if intended.count('/') == 2:
            intended_host, intended_repo = intended.split('/', 1)
            intended = intended_host.lower().removeprefix('www.') + '/' + intended_repo
        else:
            intended = (gh_host or 'github.com') + '/' + intended
        run = subprocess.run(['bash', str(scripts / script), '42', '2'], cwd=state,
                             env=env, capture_output=True, text=True, errors='backslashreplace', timeout=10)
        (state / 'output.log').write_text(run.stdout + run.stderr)
        calls = [json.loads(line) for line in (state / 'calls.jsonl').read_text().splitlines()] if (state / 'calls.jsonl').exists() else []
        wrong = [c for c in calls if c['target'] != intended]
        writes = [c for c in calls if c['mutation']]
        wrong_writes = [c for c in wrong if c['mutation']]
        # Valid runs must exercise their write path, not merely exit early.
        expected_write = 'resolveReviewThread' if helper == 'resolve' else 'requested_reviewers'
        exercised = any(expected_write in ' '.join(c['args']) for c in writes)
        if mode == 'fallback' and helper != 'resolve':
            exercised = exercised and any(c['kind'] == 'pr' for c in writes)
        ok = not wrong and (run.returncode != 0 and not writes if invalid else run.returncode == 0 and exercised)
        group = groups['ORIGINAL' if label in {c[0] for c in cases} else 'REGRESSIONS']
        group[0] += 1
        group[1] += not ok
        group[2] += len(wrong)
        group[3] += len(wrong_writes)
        failed += not ok
        wrong_total += len(wrong)
        wrong_writes_total += len(wrong_writes)
        print(f'{"PASS" if ok else "FAIL"} {helper}/{label}: exit={run.returncode} wrong_calls={len(wrong)} wrong_mutations={len(wrong_writes)} mutations={len(writes)}', flush=True)
for name, (count, failures, wrong, mutations) in groups.items():
    print(f'{name} cases={count} failed={failures} wrong_calls={wrong} wrong_mutations={mutations}')
print(f'TOTAL cases={sum(g[0] for g in groups.values())} failed={failed} wrong_calls={wrong_total} wrong_mutations={wrong_writes_total}')
sys.exit(bool(failed))
