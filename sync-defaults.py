#!/usr/bin/env python3
"""
Sync map-state.json → index.html embedded DN/DE defaults.

Run locally:  python3 sync-defaults.py
In CI:        called automatically by .github/workflows/sync-defaults.yml
              on every push that touches map-state.json
"""
import json, os, sys

BASE = os.path.dirname(os.path.abspath(__file__))
MAP_PATH  = os.path.join(BASE, 'map-state.json')
HTML_PATH = os.path.join(BASE, 'index.html')


def esc(s):
    """Escape a value for embedding in a JS single-quoted string."""
    if s is None:
        return ''
    s = str(s)
    s = s.replace('\\', '\\\\')   # backslash  →  \\
    s = s.replace('\n', '\\n')    # newline    →  \n  (literal two chars)
    s = s.replace('\r', '')
    s = s.replace("'", "\\'")     # apostrophe →  \'
    return s


def build_dn_de(data):
    dn = ['const DN = [']
    for n in data['nodes']:
        parts = [
            f"id:'{esc(n.get('id',''))}'",
            f"label:'{esc(n.get('label',''))}'",
            f"cat:'{esc(n.get('cat',''))}'",
            f"sz:{n.get('sz', 12)}",
            f"x:{round(n.get('x', 0.5), 4)}",
            f"y:{round(n.get('y', 0.5), 4)}",
            f"type:'{esc(n.get('type',''))}'",
            f"status:'{esc(n.get('status','live'))}'",
            f"desc:'{esc(n.get('desc',''))}'",
            f"tech:'{esc(n.get('tech',''))}'",
            f"notes:'{esc(n.get('notes',''))}'",
        ]
        dn.append('  {' + ','.join(parts) + '},')
    dn.append('];')

    de = ['const DE = [']
    seen = set()
    for e in data['edges']:
        key = (e.get('s',''), e.get('t',''), e.get('label',''))
        if key in seen:
            continue
        seen.add(key)
        parts = [
            f"s:'{esc(e.get('s',''))}'",
            f"t:'{esc(e.get('t',''))}'",
        ]
        if e.get('label'):
            parts.append(f"label:'{esc(e.get('label',''))}'")
        parts.append(f"pulse:{'true' if e.get('pulse') else 'false'}")
        if e.get('dash'):
            parts.append('dash:true')
        de.append('  {' + ','.join(parts) + '},')
    de.append('];')

    return '\n'.join(dn) + '\n\n' + '\n'.join(de), len(data['nodes']), len(seen)


def main():
    with open(MAP_PATH) as f:
        data = json.load(f)

    new_block, node_count, edge_count = build_dn_de(data)

    html = open(HTML_PATH).read()

    try:
        dn_start  = html.index('const DN = [')
        de_start  = html.index('const DE = [', dn_start)
        de_end    = html.index('];', de_start) + 2
    except ValueError:
        print('ERROR: could not find DN/DE markers in index.html', file=sys.stderr)
        sys.exit(2)

    new_html = html[:dn_start] + new_block + html[de_end:]

    if new_html == html:
        print(f'✓ already in sync ({node_count} nodes, {edge_count} edges)')
        sys.exit(0)

    with open(HTML_PATH, 'w') as f:
        f.write(new_html)

    print(f'✓ synced DN/DE: {node_count} nodes, {edge_count} edges')
    sys.exit(0)


if __name__ == '__main__':
    main()
