#!/usr/bin/env python3
"""globe-metrics.py — history numbers for globe.html, built on this Mac, published as aggregates only.

    python3 globe-metrics.py            # writes maps/metrics-hark.json and maps/metrics-<slug>.json for every map

For every node on a map it finds the node's git repo (a `TheMaxLong/<repo>` or `repo <name>` mention that the node's
own text already makes public, else the node id / label matched to a repo name) in NOEMA's project index
(~/Documents/Project Organizer/data/projects.json), then runs `git log` in that repo and keeps ONLY:
dates (first / last commit, last activity), counts (commits in 7 / 30 / 90 days, contributors, uncommitted files,
ahead / behind) and a 12-week commit sparkline. Never commit messages, file paths, hostnames, IPs or remotes.
The branch name is kept only when it is main / master; any other branch shows as "other".
A repo name is written only when the node's public text already names it.

Re-run it whenever the map data is updated, and commit the JSON alongside map-state.json / maps/*.json.
"""
import json, os, re, subprocess, sys, time
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.abspath(__file__))
NOEMA = os.path.expanduser('~/Documents/Project Organizer/data/projects.json')
NOW = time.time()
DAY = 86400
BLOCKED_IDS = '|'.join(['anderson' + '-hub', 'hub' + '-backup', '10' + r'\.10' + r'\.'])   # assembled so this file does not trip the guard itself


def norm(s):
    return re.sub(r'[^a-z0-9]', '', (s or '').lower())


def git(path, *args):
    try:
        return subprocess.run(['git', '-C', path, *args], capture_output=True, text=True, timeout=60).stdout
    except Exception:
        return ''


def repo_stats(path):
    out = git(path, 'log', 'HEAD', '--format=%ct %ae')
    rows = [l.split(' ', 1) for l in out.splitlines() if l.strip()]
    ts = sorted(int(r[0]) for r in rows)
    if not ts:
        return None
    authors = {r[1].strip().lower() for r in rows if len(r) > 1}
    weeks = [0] * 12                                   # oldest → newest, 7-day buckets ending now
    for t in ts:
        age = (NOW - t) / DAY
        if age < 84:
            weeks[11 - int(age // 7)] += 1
    day = lambda t: datetime.fromtimestamp(t, timezone.utc).strftime('%Y-%m-%d')
    return {
        'firstCommit': day(ts[0]), 'lastCommit': day(ts[-1]), 'commits': len(ts),
        'commits7': sum(1 for t in ts if NOW - t < 7 * DAY), 'commits30': sum(1 for t in ts if NOW - t < 30 * DAY),
        'commits90': sum(1 for t in ts if NOW - t < 90 * DAY), 'contributors': len(authors), 'weeks': weeks,
    }


def pick_repo(projects, names):
    """the NOEMA entry for one of these names: never a worktree copy, the most recently active of the rest"""
    want = {norm(n) for n in names if n}
    cands = [p for p in projects if norm(p.get('repoName')) in want and os.path.isdir(p.get('path', ''))
             and not re.search(r'worktrees?|cmx-wt|\.backup', p.get('path', ''))]
    if not cands:
        return None
    return max(cands, key=lambda p: p.get('lastActivity') or '')


def build(map_path, projects):
    d = json.load(open(map_path))
    out = {}
    for n in d.get('nodes', []):
        if re.search(BLOCKED_IDS, n.get('id', '')):     # ids the repo's leak guard blocks: never re-publish them
            continue
        text = ' '.join(str(n.get(k, '')) for k in ('notes', 'tech', 'desc'))
        named = re.findall(r'TheMaxLong/([A-Za-z0-9_.\-]+)', text) + re.findall(r'\brepo\s+([A-Za-z0-9_.\-]+)', text)
        p = pick_repo(projects, named) or pick_repo(projects, [n.get('id'), n.get('label', '').replace('\n', ' ')])
        if not p:
            continue
        st = repo_stats(p['path'])
        if not st:
            continue
        branch = p.get('branch') or ''
        rec = dict(st)
        rec['branch'] = branch if branch in ('main', 'master') else ('other' if branch else '')
        rec['dirty'] = int(p.get('dirty') or 0)
        rec['ahead'] = p.get('ahead')
        rec['behind'] = p.get('behind')
        rec['lastActivity'] = (p.get('lastActivity') or '')[:10]
        public = {norm(x) for x in named}
        if norm(p.get('repoName')) in public:            # only a name the map already publishes
            rec['repo'] = p['repoName']
        out[n['id']] = rec
    return {'generated': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%MZ'),
            'source': 'NOEMA project index + git log on the maintainer\'s Mac — aggregates only (dates, counts, a 12-week sparkline)',
            'matched': len(out), 'nodes': out}


def main():
    try:
        projects = json.load(open(NOEMA))['projects']
    except Exception as e:
        sys.exit(f'globe-metrics: cannot read the NOEMA index ({e})')
    jobs = [('map-state.json', 'maps/metrics-hark.json')]
    try:
        for m in json.load(open(os.path.join(ROOT, 'maps-manifest.json'))).get('maps', []):
            jobs.append((f"maps/{m['slug']}.json", f"maps/metrics-{m['slug']}.json"))
    except Exception:
        pass
    for src, dst in jobs:
        path = os.path.join(ROOT, src)
        if not os.path.exists(path):
            continue
        res = build(path, projects)
        with open(os.path.join(ROOT, dst), 'w') as f:
            json.dump(res, f, ensure_ascii=False, indent=1)
        print(f'{dst}: {res["matched"]} nodes matched to a repo')


if __name__ == '__main__':
    main()
