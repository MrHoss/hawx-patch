#!/usr/bin/env bash
# Monta uma variante do patch no prefixo de TESTE, a partir do pristine.
# Uso: ./variant.sh [pristine|wvm+reg+hdr+depth]  (qualquer subconjunto de wvm,reg,hdr,depth)
set -euo pipefail

T=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$T")
GAME="/home/daniel/Games/Heroic/Prefixes/default/HAWX(TESTE)/drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X"
SP="$GAME/Data/Shaders_PC"
PRISTINE=/home/daniel/Games/Heroic/hawx-shaders-pristine
VALIDADO=/home/daniel/Games/Heroic/hawx-shaders-validado

SET=${1:-}
if [ -z "$SET" ] || [ "$SET" = "pristine" ]; then
  FIXES=""
else
  FIXES=$(echo "$SET" | tr '+' ' ')
  for g in $FIXES; do
    case $g in
      wvm|reg|hdr|depth) ;;
      *) echo "grupo desconhecido: '$g' (use wvm|reg|hdr|depth)" >&2; exit 2 ;;
    esac
  done
fi
echo "grupos: ${SET:-pristine}"

[ -d "$PRISTINE" ] || { echo "pristine nao encontrado: $PRISTINE" >&2; exit 1; }

pkill -x HAWX.exe 2>/dev/null || true
pkill -x wineserver 2>/dev/null || true
sleep 1

echo "=== variante: ${SET:-pristine}"
rm -rf "$SP"
cp -a "$PRISTINE" "$SP"

for g in $FIXES; do
  case $g in
    wvm|reg|hdr)
      n=$(python3 "$T/fix_$g.py" --apply "$SP" | tail -1)
      echo "  $g: $n"
      ;;
    depth)
      ( cd "$GAME" && patch -p1 --batch --forward --silent --no-backup-if-mismatch \
          < "$REPO/patches/hawx-wined3d-depthms-workaround.patch" )
      echo "  depth: 4 stubs (via patch, CRLF)"
      ;;
  esac
done
[ -z "$FIXES" ] && echo "  (nenhum fix aplicado)"

# sanity: contagens que definem cada grupo
# `|| true`: grep sem match devolve 1 e mataria o script com pipefail ligado
wvm=$(grep -rl --include='*.fx' -E '^\s*\(float3x3\)[A-Za-z_]' "$SP" | wc -l || true)
res=$(grep -rn --include='*.fx' -E 'register\([^)]*\)[ \t]*:[ \t]*register\(' "$SP" | grep -v '//' | wc -l || true)
hdr=$(grep -rl --include='*.fx' -E '^float bHDR[[:space:]]*:[[:space:]]*register\(c31\)' "$SP" | wc -l || true)
dep=$(grep -l Texture2DMS "$SP"/DepthMS*ToLinDepth_PS.fx 2>/dev/null | wc -l || true)
printf '  sanity: wvm=%s reserva-dupla=%s bHDR@c31=%s DepthMS-orig=%s\n' "$wvm" "$res" "$hdr" "$dep"

echo
"$T/diffprefix.sh" "$SP" "$VALIDADO" --summary 2>&1 \
  | grep -E 'so em|conteudo diferente|RESULTADO|\.fx$' | sed 's/^/  /'