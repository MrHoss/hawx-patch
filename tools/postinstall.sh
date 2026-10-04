#!/usr/bin/env bash
# postinstall.sh -- deixa um prefixo novo do H.A.W.X. igual ao prefixo validado.
#
#   ./postinstall.sh <prefixo_ou_raiz_do_jogo> [--proton <dir>] [--secs N]
#                    [--flick t1-t2] [--run]
#
# Passos: aplica os patches, forca 1920x1080 tela cheia, e prova por diff que a
# arvore ficou byte-identica ao estado validado. Com --run, ainda roda o jogo e
# relata sobrevivencia + erros de shader.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDADO="/home/daniel/Games/Heroic/hawx-shaders-validado"
PROTON="/home/daniel/.config/heroic/tools/proton/GE-Proton-latest"
SECS=70; FLICK=""; DORUN=0

TARGET="${1:?informe o prefixo ou a raiz do jogo}"; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --proton) PROTON="${2:?}"; shift 2 ;;
    --secs)   SECS="${2:?}";   shift 2 ;;
    --flick)  FLICK="${2:?}";  shift 2 ;;
    --run)    DORUN=1;         shift ;;
    *) echo "opcao desconhecida: $1" >&2; exit 2 ;;
  esac
done

# --- localiza a raiz do jogo dentro do alvo -------------------------------
if   [ -d "$TARGET/Data/Shaders_PC" ]; then GAME="$(cd "$TARGET" && pwd)"
elif [ "$(basename "$TARGET")" = Shaders_PC ]; then
  GAME="$(cd "$(dirname "$(dirname "$TARGET")")" && pwd)"
else
  REL="$(cd "$TARGET" && find . -type d -path '*Data/Shaders_PC' -print -quit 2>/dev/null |
        sed 's|^\./||;s|/Data/Shaders_PC$||')"
  [ -n "$REL" ] && GAME="$(cd "$TARGET/$REL" && pwd)"
fi
[ -n "${GAME:-}" ] && [ -d "$GAME/Data/Shaders_PC" ] ||
  { echo "nao achei Data/Shaders_PC em: $TARGET" >&2; exit 2; }
SP="$GAME/Data/Shaders_PC"

echo "=== jogo:  $GAME"
echo "=== shaders: $(find "$SP" -name '*.fx' | wc -l) .fx" \
     "| DepthMS originais=$(grep -l Texture2DMS "$SP"/DepthMS*ToLinDepth_PS.fx 2>/dev/null | wc -l)"
echo "=== proton: $PROTON"
echo

echo "--- 1) aplicando os patches"
bash "$HERE/../apply.sh" --with-depthms "$GAME" 2>&1 | sed 's/^/    /'
echo

echo "--- 2) forcando 1920x1080 tela cheia"
PREFIX=$(dirname "$(dirname "$(dirname "$(dirname "$GAME")")")")
[ -d "$PREFIX/drive_c" ] || PREFIX=$(dirname "$GAME")
n=0
for s in "$PREFIX"/drive_c/users/*/Documents/*/Profiles/_settings_*.ini \
         "$PREFIX"/drive_c/users/*/"Saved Games"/*/Profiles/_settings_*.ini; do
  [ -f "$s" ] || continue
  sed -i 's/^windowed = .*/windowed = false\r/;s/^width = .*/width = 1920\r/;s/^height = .*/height = 1080\r/' "$s" 2>/dev/null
  echo "    $(basename "$s"): windowed=false 1920x1080"
  n=$((n+1))
done
[ "$n" -eq 0 ] && echo "    (nenhum _settings_*.ini ainda -- o jogo precisa rodar uma vez)"
echo

echo "--- 3) diff contra o estado validado"
"$HERE/diffprefix.sh" "$SP" "$VALIDADO" --summary 2>&1 | sed 's/^/    /'
DIFF=$?
echo

if [ "$DORUN" = 1 ]; then
  echo "--- 4) rodando o jogo"
  ARGS=(--gamedir "$GAME" --proton "$PROTON" --label postinstall --secs "$SECS")
  [ -n "$FLICK" ] && ARGS+=(--flick "$FLICK")
  "$HERE/verifyrun.sh" "${ARGS[@]}"
else
  echo "--- 4) pulado (use --run para rodar o jogo)"
fi

echo "DONE"