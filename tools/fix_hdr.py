#!/usr/bin/env python3
"""bHDR: o engine passa o flag de HDR como FLOAT em c31 (log d3d9: 1664x
SetPixelShaderConstantF reg_idx 31, e NENHUM SetBoolConstant no jogo todo).
Logo o binding util e' `float bHDR : register(c31);` -- igual ao patch
'reliade' que o autor aplicou em CromaKey. Ler de b0 (nunca setado) era o
que fazia o HUD do menu piscar claro/escuro.

Idempotente: aceita tanto a forma original (double binding) quanto a ja-corrigida.
"""
import os, re, sys

# uso: fix_X.py [--apply] <dir_Shaders_PC>
#   Sem --apply e so dry-run: mostra o que mudaria sem escrever nada.
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not _args:
    sys.exit(f"uso: {os.path.basename(sys.argv[0])} [--apply] <dir_Shaders_PC>")
ROOT = _args[0]

FILES = ['Hud/Tooltip_PS.fx', 'Hud/HudForeOnlyColor_PS.fx', 'Hud/HudFrame_PS.fx',
         'Hud/Menu_PS.fx', 'Hud/HudBackOnlyColor_PS.fx', 'Hud/OnlyColor_PS.fx']

# bool  bHDR : register(b0) : register(c31);   ->  float bHDR : register(c31);
DUP = re.compile(rb'^bool([ \t]+bHDR[ \t]*:[ \t]*)register\(b0\)[ \t]*:[ \t]*'
                 rb'register\(c31\)[ \t]*;', re.M)
# bool|float bHDR : register(b0);   ->  float bHDR : register(c31);
# (aceita `bool` porque fix_reg.py ja pode ter removido o segundo binding;
#  o tipo e' normalizado para `float`, que e' o que o engine de fato escreve)
B0 = re.compile(rb'^(?:bool|float)([ \t]+bHDR[ \t]*:[ \t]*)register\(b0\)[ \t]*;', re.M)

if not os.path.isdir(ROOT) or not os.listdir(ROOT):
    sys.exit(f"Shaders_PC nao encontrado em: {ROOT}\n"
             "informe o caminho: fix_X.py [--apply] <dir_Shaders_PC>")

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
print(f'\n{total} declaracao(oes) ' + ('[DRY-RUN]' if dry else '[APLICADO]'))
if not total:
    print('nada a fazer (ja aplicado)')