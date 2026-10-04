#!/usr/bin/env bash
# bisect.sh -- descobre quais grupos de fix sao realmente necessarios, no prefixo
# de teste, usando o MESMO proton que o Heroic usa nesse prefixo.
#
#   ./bisect.sh [variante ...]
#
# variantes: pristine | wvm | wvm+reg | wvm+reg+hdr | wvm+reg+hdr+depth
#
# Oraculo: o jogo com defeito trava na tela preta. Logo, brilho medio da janela
# sustentado em ~0 = travado; brilho variando = renderizando.
# No fim restaura o estado validado (inclusive em Ctrl-C).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="/home/daniel/Games/Heroic/Prefixes/default/HAWX(TESTE)"
GAME="$PREFIX/drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X"
SP="$GAME/Data/Shaders_PC"
PRISTINE="/home/daniel/Games/Heroic/hawx-shaders-pristine"
VALIDADO="/home/daniel/Games/Heroic/hawx-shaders-validado"
PROTON="/home/daniel/.local/share/Steam/steamapps/common/Proton 10.0"
SAMPLES="${SAMPLES:-16}"     # amostras de 3s = 48s de observacao
VARIANTS=("$@")
[ ${#VARIANTS[@]} -eq 0 ] && VARIANTS=(pristine wvm wvm+reg wvm+reg+hdr wvm+reg+hdr+depth)

restaurar() {
  pkill -x HAWX.exe 2>/dev/null; pkill -x wineserver 2>/dev/null; sleep 2
  rm -rf "$SP"; cp -a "$VALIDADO" "$SP"
  echo "### estado validado restaurado no prefixo de teste"
}
trap restaurar EXIT INT TERM

ymean_win() {
  local w
  w=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+' | while read -r x; do
        case "$(xprop -id "$x" WM_CLASS 2>/dev/null)" in *steam_proton*) echo "$x"; break ;; esac
      done)
  [ -n "$w" ] || { echo ""; return; }
  timeout 6 import -window "$w" -silent /tmp/.bz.png 2>/dev/null || { echo ""; return; }
  python3 "$HERE/ymean.py" < /tmp/.bz.png 2>/dev/null
}

for VARIANT in "${VARIANTS[@]}"; do
  echo "==================================================================="
  echo "### variante: $VARIANT"
  pkill -x HAWX.exe 2>/dev/null; pkill -x wineserver 2>/dev/null; sleep 2
  rm -rf "$SP"; cp -a "$PRISTINE" "$SP"
  if [ "$VARIANT" != pristine ]; then
    for g in ${VARIANT//+/ }; do
      case "$g" in
        wvm|reg|hdr) python3 "$HERE/fix_$g.py" --apply "$SP" | tail -1 | sed 's/^/    /' ;;
        depth) for n in 16 08 04 02; do
                  printf 'float4 main(float4 c : COLOR) : COLOR\r\n{\r\n\treturn float4(0.0f, 0.0f, 0.0f, 1.0f);\r\n}\r\n' \
                    > "$SP/DepthMS${n}ToLinDepth_PS.fx"; done
                echo "    depth: 4 stubs" ;;
        *) echo "    grupo desconhecido: $g" ;;
      esac
    done
  fi
  echo "    DepthMS originais=$(grep -l Texture2DMS "$SP"/DepthMS*ToLinDepth_PS.fx 2>/dev/null | wc -l)"

  WINEPREFIX="$PREFIX" STEAM_COMPAT_DATA_PATH="$PREFIX" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/daniel/.local/share/Steam \
    WINEDEBUG=-all setsid "$PROTON/proton" run "$GAME/HAWX.exe" >/tmp/bisect.log 2>&1 </dev/null &
  sleep 18

  vals=()
  for k in $(seq 1 "$SAMPLES"); do sleep 3; vals+=("$(ymean_win)"); done
  alive=$(pgrep -x HAWX.exe | wc -l)
  pkill -x HAWX.exe 2>/dev/null; sleep 1; pkill -x wineserver 2>/dev/null

  printf '    brilho: %s\n' "${vals[*]}"
  last5=$(printf '%s\n' "${vals[@]: -5}" | tr -d ' ' | grep -c '^0\.')
  nonZero=$(printf '%s\n' "${vals[@]}" | tr -d ' ' | awk '$1>1.0' | wc -l)
  if [ "$alive" -eq 0 ]; then
    VERDICT="MORREU/ENCERRADO"
  elif [ "$last5" -ge 4 ] && [ "$nonZero" -le 3 ]; then
    VERDICT="TRAVADO (preto no final)"
  else
    VERDICT="OK (renderizando)"
  fi
  echo "    processos vivos: $alive | amostras >1.0: $nonZero | VEREDITO: $VERDICT"
  echo "    log: /tmp/bisect.log"
done