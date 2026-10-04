#!/usr/bin/env bash
# diffprefix.sh -- compara duas arvores Data/Shaders_PC e mostra o que difere.
#
#   ./diffprefix.sh <dirA> <dirB>            # resumo + diff unificado
#   ./diffprefix.sh <dirA> <dirB> --summary  # so o resumo
#
# Exit: 0 = identicas, 1 = ha diferencas, 2 = erro de uso.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

A="${1:?}"; B="${2:?}"; MODE="${3:-}"
[ -d "$A" ] && [ -d "$B" ] || { echo "uso: $0 <dirA> <dirB> [--summary]" >&2; exit 2; }
A="$(cd "$A" && pwd)"; B="$(cd "$B" && pwd)"

"$HERE/manifest.sh" "$A" /tmp/.mA.txt | sed 's/^/  /'
"$HERE/manifest.sh" "$B" /tmp/.mB.txt | sed 's/^/  /'

echo
echo "=== A: $A"
echo "=== B: $B"
echo

# manifest.sh ja emite ordenado por caminho (LC_ALL=C sort -k2), entao o awk
# so precisa casar por nome. Nao usar comm/join: eles ordenariam por hash.
awk '
  FNR==NR { bh[$2]=$1; next }
  { ah[$2]=$1 }
  END {
    for (p in ah) {
      if (!(p in bh))                 onlyA[++na]=p
      else if (ah[p] != bh[p])        chg[++nc]=p
    }
    for (p in bh) if (!(p in ah)) onlyB[++nb]=p
    printf "--- so em A: %d\n", na+0
    for (i=1;i<=na;i++) printf "      %s\n", onlyA[i]
    printf "--- so em B: %d\n", nb+0
    for (i=1;i<=nb;i++) printf "      %s\n", onlyB[i]
    printf "--- conteudo diferente: %d\n", nc+0
    for (i=1;i<=nc;i++) printf "      %s\n", chg[i]
    printf "TOTAL %d\n", na+nb+nc
  }
' /tmp/.mB.txt /tmp/.mA.txt > /tmp/.cmp

grep -v '^TOTAL ' /tmp/.cmp
TOTAL=$(awk '/^TOTAL /{print $2}' /tmp/.cmp)
CHG=$(awk '/^--- conteudo diferente: /{f=1;next} /^TOTAL /{f=0} f&&NF' /tmp/.cmp)

if [ "$MODE" != "--summary" ] && [ -n "$CHG" ]; then
  echo
  echo "=== diff unificado (A -> B) ==="
  printf '%s\n' "$CHG" | while read -r f; do
    diff -u --label "A/$f" --label "B/$f" "$A/$f" "$B/$f" || true
  done
fi

echo
[ "$TOTAL" -eq 0 ] && { echo "RESULTADO: identicas"; exit 0; }
echo "RESULTADO: $TOTAL arquivo(s) diferem"; exit 1