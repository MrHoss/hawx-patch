#!/usr/bin/env python3
"""bHDR: the engine passes the HDR flag as a FLOAT in c31 (d3d9 log: 1664x
SetPixelShaderConstantF reg_idx 31, and NO SetBoolConstant anywhere in the game).
So the binding in use is `float bHDR : register(c31);` -- same as the
'reliade' patch the author applied to CromaKey. Reading it from b0 (never set)
is what made the menu HUD flicker light/dark.

Idempotent: accepts both the original form (double binding) and the already
fixed one.
"""
import os, re, sys

# usage: fix_X.py [--apply] <dir_Shaders_PC>
#   Without --apply it is a dry run: shows what would change, writes nothing.
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not _args:
    sys.exit(f"usage: {os.path.basename(sys.argv[0])} [--apply] <dir_Shaders_PC>")
ROOT = _args[0]

FILES = ['Hud/Tooltip_PS.fx', 'Hud/HudForeOnlyColor_PS.fx', 'Hud/HudFrame_PS.fx',
         'Hud/Menu_PS.fx', 'Hud/HudBackOnlyColor_PS.fx', 'Hud/OnlyColor_PS.fx']

# bool  bHDR : register(b0) : register(c31);   ->  float bHDR : register(c31);
DUP = re.compile(rb'^bool([ \t]+bHDR[ \t]*:[ \t]*)register\(b0\)[ \t]*:[ \t]*'
                 rb'register\(c31\)[ \t]*;', re.M)
# bool|float bHDR : register(b0);   ->  float bHDR : register(c31);
# (`bool` is accepted because fix_reg.py may already have removed the second
#  binding; the type is normalised to `float`, which is what the engine writes)
B0 = re.compile(rb'^(?:bool|float)([ \t]+bHDR[ \t]*:[ \t]*)register\(b0\)[ \t]*;', re.M)

if not os.path.isdir(ROOT) or not os.listdir(ROOT):
    sys.exit(f"Shaders_PC not found in: {ROOT}\n"
             "pass the path: fix_X.py [--apply] <dir_Shaders_PC>")

dry = '--apply' not in sys.argv
total = 0
for rel in FILES:
    p = os.path.join(ROOT, rel)
    b = open(p, 'rb').read()
    nb, n = DUP.subn(rb'float\g<1>register(c31);', b)
    nb, n2 = B0.subn(rb'float\g<1>register(c31);', nb)
    n += n2
    if n:
        total += n
        print(f'  {rel}: {n}')
        if not dry:
            open(p, 'wb').write(nb)
print(f'\n{total} declaration(s) ' + ('[DRY-RUN]' if dry else '[APPLIED]'))
if not total:
    print('nothing to do (already applied)')