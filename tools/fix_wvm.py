#!/usr/bin/env python3
"""Replaces `(float3x3)X = mul(...)` (size change on the LHS, E5017 in vkd3d)
with a temporary float3x3 + per-column assignment. Preserves CRLF."""
import glob, os, re, sys

# usage: fix_X.py [--apply] <dir_Shaders_PC>
#   Without --apply it is a dry run: shows what would change, writes nothing.
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not _args:
    sys.exit(f"usage: {os.path.basename(sys.argv[0])} [--apply] <dir_Shaders_PC>")
ROOT = _args[0]

PAT = re.compile(
    rb'^([ \t]*)\(float3x3\)([A-Za-z_]\w*)[ \t]*=[ \t]*(mul\([^;]*\));([ \t]*\r?)(?=\n)',
    re.M)


def repl(m):
    ws, dst, expr, eol = m.groups()
    return (ws + b'float3x3 _hawx_wvm3 = ' + expr + b';' + eol + b'\n'
            + ws + dst + b'[0] = float4(_hawx_wvm3[0], 0.0);' + eol + b'\n'
            + ws + dst + b'[1] = float4(_hawx_wvm3[1], 0.0);' + eol + b'\n'
            + ws + dst + b'[2] = float4(_hawx_wvm3[2], 0.0);' + eol)


if not os.path.isdir(ROOT) or not os.listdir(ROOT):
    sys.exit(f"Shaders_PC not found in: {ROOT}\n"
             "pass the path: fix_X.py [--apply] <dir_Shaders_PC>")

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
print(f'\n{total_subs} substitution(s) in {total_files} file(s)'
      f'{" [DRY-RUN]" if dry else " [APPLIED]"}')