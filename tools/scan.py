#!/usr/bin/env python3
"""Scan every .fx with vkd3d-compiler looking for HLSL errors.

Usage: scan.py [substring-to-match]
"""
import glob, os, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = ("/home/daniel/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X./"
        "drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X/Data/Shaders_PC")
TOOL = "/tmp/hawxfix/vkd3d/usr/bin/vkd3d-compiler"
ENV = dict(os.environ, LD_LIBRARY_PATH="/tmp/hawxfix/vkd3d/usr/lib")

WANT = (sys.argv[1] if len(sys.argv) > 1 else "Size change on the LHS").lower()

inc_re = re.compile(r'^\s*#\s*include\s+"([^"]+)"\s*$')

def expand(path, seen=None):
    """Inline #include "..." the way the game's preprocessor would."""
    seen = seen or set()
    rp = os.path.realpath(path)
    if rp in seen:
        return ""
    seen.add(rp)
    out = []
    d = os.path.dirname(path)
    try:
        lines = open(path, encoding='latin-1').read().split('\n')
    except OSError:
        return ""
    for ln in lines:
        m = inc_re.match(ln)
        if not m:
            out.append(ln)
            continue
        name = m.group(1)
        for cand in (os.path.join(d, name), os.path.join(ROOT, name),
                     os.path.join(os.path.dirname(d), name)):
            if os.path.isfile(cand):
                out.append(expand(cand, seen))
                break
        else:
            out.append(ln)          # leave it; compiler will complain
    return '\n'.join(out)


def stage_of(rel):
    b = os.path.basename(rel)
    if re.search(r'(^|[_.\-])(vs|VS|vert)', b):
        return 'vs'
    if re.search(r'(^|[_.\-])(ps|PS|pix|frag)', b):
        return 'ps'
    return None


PROFILES = {
    'vs': [('vs_4_0', 'dxbc-tpf'), ('vs_3_0', 'd3dbc'), ('vs_2_0', 'd3dbc')],
    'ps': [('ps_4_0', 'dxbc-tpf'), ('ps_3_0', 'd3dbc'), ('ps_2_0', 'd3dbc')],
}


def test(path):
    rel = os.path.relpath(path, ROOT)
    src = expand(path)
    st = stage_of(rel)
    stages = [st] if st else ['vs', 'ps']
    res = []
    for s in stages:
        for prof, tgt in PROFILES[s]:
            with tempfile.NamedTemporaryFile('w', suffix='.fx', delete=False,
                                             encoding='latin-1') as fh:
                fh.write(src)
                tmp = fh.name
            try:
                p = subprocess.run([TOOL, '-e', 'main', '-p', prof, '-b', tgt, tmp],
                                   capture_output=True, timeout=30, env=ENV)
                err = (p.stderr or b'').decode('latin-1') + \
                      (p.stdout or b'').decode('latin-1')
            except subprocess.TimeoutExpired:
                err = 'TIMEOUT'
            finally:
                os.unlink(tmp)
            if WANT in err.lower():
                keep = [l for l in err.splitlines()
                        if WANT in l.lower() or 'error' in l.lower()]
                res.append((rel, prof, keep[:3]))
    return res


files = sorted(glob.glob(os.path.join(ROOT, '**', '*.fx'), recursive=True))
print(f'{len(files)} arquivos .fx; procurando: {WANT!r}\n', flush=True)

hits = []
done = 0
with ThreadPoolExecutor(max_workers=8) as ex:
    for r in ex.map(test, files):
        done += 1
        if r:
            hits.extend(r)
            for rel, prof, keep in r:
                print(f'>>> {rel}  [{prof}]')
                for k in keep:
                    print(f'      {k.strip()}')
        if done % 100 == 0:
            print(f'  ...{done}/{len(files)}', flush=True)

print(f'\n=== {len(hits)} arquivo(s) com o erro ===')
for rel, prof, keep in hits:
    print(f'  {rel} [{prof}]: {keep[0].strip() if keep else ""}')
