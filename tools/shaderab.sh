#!/usr/bin/env bash
# shaderab.sh -- troca a arvore de shaders do jogo por uma de referencia, roda o
# jogo com um proton e RESTAURA o estado validado ao final (sempre, inclusive em
# Ctrl-C). Existe para poder testar os shaders originais sem risco.
#
#   ./shaderab.sh <arvore_referencia> <proton_dir> <label> [opcoes do verifyrun.sh]
#
# Exemplo:
#   ./shaderab.sh ~/Games/Heroic/hawx-shaders-pristine \
#       ~/.config/heroic/tools/proton/Proton-CachyOS-latest pristine_cachyos --fs
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME="/home/daniel/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X./drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X"
SP="$GAME/Data/Shaders_PC"
VALIDADO="/home/daniel/Games/Heroic/hawx-shaders-validado"

TREE="${1:?arvore de referencia}"; PROTON="${2:?proton}"; LABEL="${3:?label}"; shift 3
[ -d "$TREE" ] || { echo "arvore inexistente: $TREE" >&2; exit 2; }
[ -d "$VALIDADO" ] || { echo "sem snapshot validado em $VALIDADO -- recusa trocar" >&2; exit 2; }

restaurar() {
  rm -rf "$SP"
  cp -a "$VALIDADO" "$SP"
  n=$(find "$SP" -name '*.fx' | wc -l)
  d=$(grep -l Texture2DMS "$SP"/DepthMS*ToLinDepth_PS.fx 2>/dev/null | wc -l)
  echo "### estado validado restaurado: $n .fx | DepthMS originais=$d"
}
trap restaurar EXIT INT TERM

echo "### trocando para a arvore de referencia: $TREE"
rm -rf "$SP"
cp -a "$TREE" "$SP"
echo "### em uso: $(find "$SP" -name '*.fx' | wc -l) .fx | DepthMS originais=$(grep -l Texture2DMS "$SP"/DepthMS*ToLinDepth_PS.fx 2>/dev/null | wc -l)"
echo

"$HERE/verifyrun.sh" --gamedir "$GAME" --proton "$PROTON" --label "$LABEL" "$@"