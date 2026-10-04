#!/usr/bin/env python3
"""Substitui `(float3x3)X = mul(...)` (size change on the LHS, E5017 no vkd3d)
por temporario float3x3 + atribuicao coluna a coluna. Preserva CRLF."""
import glob, os, re, sys

ROOT = ("/home/daniel/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X./"
        "drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X/Data/Shaders_PC")

PAT = re.compile(
    rb'^([ \t]*)\(float3x3\)([A-Za-z_]\w*)[ \t]*=[ \t]*(mul\([^;]*\));([ \t]*\r?)(?=\n)',
    re.M)


def repl(m):
    ws, dst, expr, eol = m.groups()
    return (ws + b'float3x3 _hawx_wvm3 = ' + expr + b';' + eol + b'\n'
            + ws + dst + b'[0] = float4(_hawx_wvm3[0], 0.0);' + eol + b'\n'
            + ws + dst + b'[1] = float4(_hawx_wvm3[1], 0.0);' + eol + b'\n'
            + ws + dst + b'[2] = float4(_hawx_wvm3[2], 0.0);' + eol)


dry = '--apply' not in sys.argv
total_files = total_subs = 0
for p in sorted(glob.glob(os.path.join(ROOT, '**', '*.fx'), recursive=True)):
    b = open(p, 'rb').read()
    nb, n = PAT.subn(repl, b)
    if not n:
        continue
    total_files += 1
    total_subs += n
    print(f'  {os.path.relpath(p, ROOT)}: {n}')
    if not dry:
        open(p, 'wb').write(nb)
print(f'\n{total_subs} substituicao(oes) em {total_files} arquivo(s)'
      f'{" [DRY-RUN]" if dry else " [APLICADO]"}')