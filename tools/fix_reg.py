#!/usr/bin/env python3
"""Removes the second `: register(cN)` reservation (E5017 'Multiple register()
reservations' in vkd3d). Keeps the first one, which is the one fxc uses."""
import glob, os, re, sys

# usage: fix_X.py [--apply] <dir_Shaders_PC>
#   Without --apply it is a dry run: shows what would change, writes nothing.
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not _args:
    sys.exit(f"usage: {os.path.basename(sys.argv[0])} [--apply] <dir_Shaders_PC>")
ROOT = _args[0]

# name : register(bN) : register(cM);   ->  name : register(bN);
PAT = re.compile(
    rb'^([ \t]*\w+[ \t]+\w+[ \t]*:[ \t]*register\([^)]*\))[ \t]*:[ \t]*register\([^)]*\)[ \t]*;',
    re.M)

if not os.path.isdir(ROOT) or not os.listdir(ROOT):
    sys.exit(f"Shaders_PC not found in: {ROOT}\n"
             "pass the path: fix_X.py [--apply] <dir_Shaders_PC>")

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
print(f'\n{subs} duplicate reservation(s) removed in {files} file(s)'
      f'{" [DRY-RUN]" if dry else " [APPLIED]"}')