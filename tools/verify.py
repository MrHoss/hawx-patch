#!/usr/bin/env python3
"""Compila apenas os arquivos indicados e mostra os erros. Uso: verify.py <rel1> [rel2..]"""
import os, re, subprocess, sys, tempfile

ROOT = ("/home/daniel/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X./"
        "drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X/Data/Shaders_PC")
TOOL = "/tmp/hawxfix/vkd3d/usr/bin/vkd3d-compiler"
ENV = dict(os.environ, LD_LIBRARY_PATH="/tmp/hawxfix/vkd3d/usr/lib")
inc_re = re.compile(r'^\s*#\s*include\s+"([^"]+)"\s*$')


def expand(path, seen=None):
    seen = seen or set()
    rp = os.path.realpath(path)
    if rp in seen:
        return ""
    seen.add(rp)
    out, d = [], os.path.dirname(path)
    try:
        lines = open(path, encoding='latin-1').read().split('\n')
    except OSError:
        return ""
    for ln in lines:
        m = inc_re.match(ln)
        if not m:
            out.append(ln)
            continue
        name = m.group(1).replace('\\', '/')
        base = os.path.dirname(d)
        cands = [os.path.join(d, name), os.path.join(ROOT, name)]
        for _ in range(4):
            cands.append(os.path.join(base, name))
            base = os.path.dirname(base)
        for c in cands:
            if os.path.isfile(c):
                out.append(expand(c, seen))
                break
        else:
            out.append(ln)
    return '\n'.join(out)


def stage_of(rel):
    b = os.path.basename(rel)
    if re.search(r'(^|[_.\-])(vs|VS|vert)', b):
        return 'vs'
    if re.search(r'(^|[_.\-])(ps|PS|pix|frag)', b):
        return 'ps'
    return None


PROF = {'vs': [('vs_4_0', 'dxbc-tpf'), ('vs_3_0', 'd3dbc')],
        'ps': [('ps_4_0', 'dxbc-tpf'), ('ps_3_0', 'd3dbc')]}

bad = 0
for rel in sys.argv[1:]:
    src = expand(os.path.join(ROOT, rel))
    for st in ([stage_of(rel)] if stage_of(rel) else ['vs', 'ps']):
        for prof, tgt in PROF[st]:
            with tempfile.NamedTemporaryFile('w', suffix='.fx', delete=False,
                                             encoding='latin-1') as fh:
                fh.write(src)
                tmp = fh.name
            try:
                p = subprocess.run([TOOL, '-e', 'main', '-p', prof, '-b', tgt, tmp],
                                   capture_output=True, timeout=30, env=ENV)
                err = (p.stderr or b'').decode('latin-1') + (p.stdout or b'').decode('latin-1')
                rc = p.returncode
            except subprocess.TimeoutExpired:
                err, rc = 'TIMEOUT', -1
            finally:
                os.unlink(tmp)
            errs = [l.strip() for l in err.splitlines() if re.search(r'E\d+:', l)]
            if errs:
                bad += 1
                print(f'  [ERRO] {rel} [{prof}]')
                for e in errs[:4]:
                    print(f'          {e}')
            else:
                print(f'  [ok]   {rel} [{prof}] rc={rc}')
print(f'\n{bad} combinacao(oes) com erro')