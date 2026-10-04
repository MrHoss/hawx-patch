#!/usr/bin/env python3
"""Substitui `(float3x3)X = mul(...)` (size change on the LHS, E5017 no vkd3d)
por temporario float3x3 + atribuicao coluna a coluna. Preserva CRLF."""
import glob, os, re, sys

# Sem argumento, usa $HAWX_GAME_DIR ou a raiz do prefixo deste usuario.
_env = os.environ.get("HAWX_GAME_DIR", "").rstrip("/")
_default = _env + "/Data/Shaders_PC" if _env else (
    os.path.expanduser("~/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X./"
                        "drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X/"
                        "Data/Shaders_PC"))
# uso: fix_X.py [--apply] [dir_Shaders_PC]
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
ROOT = _args[0] if _args else ROOT_DEFAULT

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
    sys.exit(f"Shaders_PC nao encontrado em: {ROOT}\n"
             "informe o caminho: fix_X.py [--apply] <dir_Shaders_PC>")

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