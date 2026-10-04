#!/usr/bin/env python3
"""Remove a segunda reserva `: register(cN)` (E5017 'Multiple register()
reservations' no vkd3d). Mantem a primeira, que e a que o fxc usa."""
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

# name : register(bN) : register(cM);   ->  name : register(bN);
PAT = re.compile(
    rb'^([ \t]*\w+[ \t]+\w+[ \t]*:[ \t]*register\([^)]*\))[ \t]*:[ \t]*register\([^)]*\)[ \t]*;',
    re.M)

if not os.path.isdir(ROOT) or not os.listdir(ROOT):
    sys.exit(f"Shaders_PC nao encontrado em: {ROOT}\n"
             "informe o caminho: fix_X.py [--apply] <dir_Shaders_PC>")

dry = '--apply' not in sys.argv
files = subs = 0
for p in sorted(glob.glob(os.path.join(ROOT, '**', '*.fx'), recursive=True)):
    b = open(p, 'rb').read()
    nb, n = PAT.subn(rb'\1;', b)
    if not n:
        continue
    files += 1
    subs += n
    print(f'  {os.path.relpath(p, ROOT)}: {n}')
    if not dry:
        open(p, 'wb').write(nb)
print(f'\n{subs} reserva(s) dupla(s) removida(s) em {files} arquivo(s)'
      f'{" [DRY-RUN]" if dry else " [APLICADO]"}')