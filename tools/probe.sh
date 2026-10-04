#!/usr/bin/env bash
# probe.sh -- restaura um conjunto de fixes, roda o jogo e reporta os erros de
# shader que o proprio jogo logar (D3DCompile2 -> vkd3d). Como o jogo aborta no
# PRIMEIRO shader que falha, cada rodada revela o proximo bloqueio.
#
#   ./probe.sh pristine 90
#   ./probe.sh wvm+reg+hdr+depth 90
#   ./probe.sh patched 90            # = todos os 4 grupos de shader
#
# Grupos:
#   wvm    E5017 Size change on the LHS            (29 arquivos)
#   reg    E5017 Multiple register() reservations (20 arquivos)
#   hdr    bHDR: register(b0) -> register(c31)    ( 6 arquivos)
#   depth  DepthMS* Texture2DMS -> stub           ( 4 arquivos)
#   off    resolucao/tela cheia (fora da arvore de shaders)
set -uo pipefail

GAMEDIR="/home/daniel/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X./drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X"
PRISTINE="/home/daniel/Games/Heroic/hawx-shaders-pristine"
TOOLS="/home/daniel/Games/Heroic/hawx-patch/tools"
SETTINGS="/home/daniel/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X./drive_c/users/daniel/Documents/Tom Clancy's H.A.W.X/Profiles/_settings_0.1.525.ini"

VARIANT="${1:-pristine}"
SECS="${2:-75}"
SP="$GAMEDIR/Data/Shaders_PC"

# SEGURANCA: este script DESTRUI a arvore de shaders do jogo para montar a
# variante e so no fim recoloca o estado validado. Sem isso, um probe
# interrompido deixa o jogo com patch pela metade -- foi o que causou a
# regressao de "menu piscando" relatada pelo usuario.
restore_validated() {
  bash "$TOOLS/../apply.sh" --with-depthms >/dev/null 2>&1 \
    && echo "=== estado validado restaurado (main + depthms) ===" \
    || echo "!!! FALHA ao restaurar o estado validado -- rode: $TOOLS/../apply.sh --with-depthms" >&2
}
trap restore_validated EXIT INT TERM

echo "=== restaurando variante: $VARIANT ==="
rm -rf "$SP"
cp -a "$PRISTINE" "$SP"

if [ "$VARIANT" != pristine ]; then
  FIXSET="${VARIANT//+/ }"
  case "$FIXSET" in *patched*) FIXSET="wvm reg hdr depth";; esac
  for g in $FIXSET; do
    case "$g" in
      wvm|reg|hdr) python3 "$TOOLS/fix_$g.py" --apply | tail -1 ;;
      depth)
        for n in 16 08 04 02; do
          printf 'float4 main(float4 c : COLOR) : COLOR\r\n{\r\n\treturn float4(0.0f, 0.0f, 0.0f, 1.0f);\r\n}\r\n' \
            > "$SP/DepthMS${n}ToLinDepth_PS.fx"
        done
        echo "  depth: 4 stubs DepthMS" ;;
      off)
        sed -i 's/^windowed = .*/windowed = false\r/;s/^width = .*/width = 1920\r/;s/^height = .*/height = 1080\r/' "$SETTINGS" 2>/dev/null
        echo "  off: tela cheia 1920x1080" ;;
      *) echo "grupo desconhecido: $g" >&2; exit 2 ;;
    esac
  done
fi
[ "$VARIANT" = pristine ] || [ "$VARIANT" = off ] || true

echo "=== sanity: padroes restantes ==="
printf '  cast-LHS: %s | reserva dupla: %s | bHDR@c31: %s | DepthMS originais: %s\n' \
  "$(grep -rl --include=*.fx -E '^\s*\(float3x3\)[A-Za-z_]' "$SP" | wc -l)" \
  "$(grep -rn --include=*.fx -E 'register\([^)]*\)[ \t]*:[ \t]*register\(' "$SP" | grep -v '//' | wc -l)" \
  "$(grep -rl --include=*.fx 'bHDR.*register(c31)' "$SP" | wc -l)" \
  "$(grep -l Texture2DMS "$SP"/DepthMS*ToLinDepth_PS.fx 2>/dev/null | wc -l)"

pkill -x HAWX.exe 2>/dev/null; pkill -x wineserver 2>/dev/null; sleep 1

echo "=== rodando o jogo por ${SECS}s ==="
P="/home/daniel/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X."
PRD=/home/daniel/.config/heroic/tools/proton/GE-Proton-latest
export WINEPREFIX="$P" STEAM_COMPAT_DATA_PATH="$P" \
  STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/daniel/.local/share/Steam \
  WINEDEBUG=fixme-all PROTON_USE_WINED3D=1
LOG=/tmp/probe.log
setsid "$PRD/proton" run "$GAMEDIR/HAWX.exe" >"$LOG" 2>&1 </dev/null &
for i in $(seq 1 80); do q=$(pgrep -x HAWX.exe | head -1); [ -n "$q" ] && break; sleep 0.3; done
[ -z "$q" ] && { echo "  jogo nem iniciou"; tail -5 "$LOG"; exit 1; }

# medicao opcional de cintilacao, no formato "t1-t2" em segundos de jogo.
# A sessao e Wayland: o root do XWayland e preto, entao medimos a janela do jogo.
FLICK="${3:-}"
WIN=""
find_gamewin() {
  xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+' | while read -r w; do
    case "$(xprop -id "$w" WM_CLASS 2>/dev/null)" in
      *steam_proton*|*HAWX*) echo "$w"; break ;;
    esac
  done
}
if [ -n "$FLICK" ]; then
  for i in $(seq 1 100); do WIN=$(find_gamewin); [ -n "$WIN" ] && break; sleep 0.5; done
  if [ -z "$WIN" ]; then echo "  janela do jogo nao apareceu (pulando medicao)"; else
    t1="${FLICK%%-*}"; t2="${FLICK##*-}"
    echo "=== flicker: janela $WIN, medindo ${t1}s-${t2}s ==="
    sleep "$t1"
    "$TOOLS/flicker.sh" "$((t2-t1))" "/tmp/flicker_$(echo "$VARIANT" | tr '+ ' '__').csv"
  fi
fi

died=""
for k in $(seq 1 "$SECS"); do
  sleep 1
  kill -0 "$q" 2>/dev/null || { died=$k; break; }
done
if [ -n "$died" ]; then echo "  JOGO MORREU em ${died}s"; else
  echo "  JOGO SOBREVIVEU ${SECS}s (cpu=$(ps -o pcpu= -p $q | tr -d ' '))"
fi
pkill -x HAWX.exe 2>/dev/null; sleep 1; pkill -x wineserver 2>/dev/null


echo
echo "=== erros de shader (E*) ==="
grep -oE '\S*\.fx:[0-9]+:[0-9]+: E[0-9]+: .*|<anonymous>:[0-9]+:[0-9]+: E[0-9]+: .*' "$LOG" | sort -u | sed 's|Data/Shaders_PC/||;s/^/  /'
if ! grep -qE ': E[0-9]+:' "$LOG"; then echo "  (nenhum)"; fi
echo "=== avisos (W*) ==="
grep -oE '(\.fx|anonymous)[^ ]*: W[0-9]+: .*' "$LOG" | sort -u | sed 's/^/  /' | head -10
grep -qE ': W[0-9]+:' "$LOG" || echo "  (nenhum)"
exit 0