#!/usr/bin/env python3
"""bHDR: o engine passa o flag de HDR como FLOAT em c31 (log d3d9: 1664x
SetPixelShaderConstantF reg_idx 31, e NENHUM SetBoolConstant no jogo todo).
Logo o binding util e' `float bHDR : register(c31);` -- igual ao patch
'reliade' que o autor aplicou em CromaKey. Ler de b0 (nunca setado) era o
que fazia o HUD do menu piscar claro/escuro.

Idempotente: aceita tanto a forma original (double binding) quanto a ja-corrigida.
"""
import os, re, sys

ROOT_DEFAULT = ("/home/daniel/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X./"
                "drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X/Data/Shaders_PC")
# uso: fix_X.py [--apply] [dir_Shaders_PC]
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
ROOT = _args[0] if _args else ROOT_DEFAULT

FILES = ['Hud/Tooltip_PS.fx', 'Hud/HudForeOnlyColor_PS.fx', 'Hud/HudFrame_PS.fx',
         'Hud/Menu_PS.fx', 'Hud/HudBackOnlyColor_PS.fx', 'Hud/OnlyColor_PS.fx']

# bool  bHDR : register(b0) : register(c31);   ->  float bHDR : register(c31);
DUP = re.compile(rb'^bool([ \t]+bHDR[ \t]*:[ \t]*)register\(b0\)[ \t]*:[ \t]*'
                 rb'register\(c31\)[ \t]*;', re.M)
# float bHDR : register(b0);   ->  float bHDR : register(c31);
B0 = re.compile(rb'^(float[ \t]+bHDR[ \t]*:[ \t]*)register\(b0\)[ \t]*;', re.M)

dry = '--apply' not in sys.argv
total = 0
for rel in FILES:
    p = os.path.join(ROOT, rel)
    b = open(p, 'rb').read()
    nb, n = DUP.subn(rb'float\g<1>register(c31);', b)
    nb, n2 = B0.subn(rb'\g<1>register(c31);', nb)
    n += n2
    if n:
        total += n
        print(f'  {rel}: {n}')
        if not dry:
            open(p, 'wb').write(nb)
print(f'\n{total} declaracao(oes) ' + ('[DRY-RUN]' if dry else '[APLICADO]'))
if not total:
    print('nada a fazer (ja aplicado)')