#!/usr/bin/env bash
# diffprefix.sh -- compare two Data/Shaders_PC trees and show what differs.
#
#   ./diffprefix.sh <dirA> <dirB>            # summary + unified diff
#   ./diffprefix.sh <dirA> <dirB> --summary  # summary only
#
# Exit: 0 = identical, 1 = differences found, 2 = usage error.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

A="${1:?}"; B="${2:?}"; MODE="${3:-}"
[ -d "$A" ] && [ -d "$B" ] || { echo "usage: $0 <dirA> <dirB> [--summary]" >&2; exit 2; }
A="$(cd "$A" && pwd)"; B="$(cd "$B" && pwd)"

"$HERE/manifest.sh" "$A" /tmp/.mA.txt | sed 's/^/  /'
"$HERE/manifest.sh" "$B" /tmp/.mB.txt | sed 's/^/  /'

echo
echo "=== A: $A"
echo "=== B: $B"
echo

# manifest.sh already emits entries sorted by path (LC_ALL=C sort -k2), so the
# awk below only has to match by name. Do not use comm/join: they would sort by
# hash instead.
awk '
  FNR==NR { bh[$2]=$1; next }
  { ah[$2]=$1 }
  END {
    for (p in ah) {
      if (!(p in bh))                 onlyA[++na]=p
      else if (ah[p] != bh[p])        chg[++nc]=p
    }
    for (p in bh) if (!(p in ah)) onlyB[++nb]=p
    printf "--- only in A: %d\n", na+0
    for (i=1;i<=na;i++) printf "      %s\n", onlyA[i]
    printf "--- only in B: %d\n", nb+0
    for (i=1;i<=nb;i++) printf "      %s\n", onlyB[i]
    printf "--- content differs: %d\n", nc+0
    for (i=1;i<=nc;i++) printf "      %s\n", chg[i]
    printf "TOTAL %d\n", na+nb+nc
  }
' /tmp/.mB.txt /tmp/.mA.txt > /tmp/.cmp

grep -v '^TOTAL ' /tmp/.cmp
TOTAL=$(awk '/^TOTAL /{print $2}' /tmp/.cmp)
CHG=$(awk '/^--- content differs: /{f=1;next} /^TOTAL /{f=0} f&&NF' /tmp/.cmp)

if [ "$MODE" != "--summary" ] && [ -n "$CHG" ]; then
  echo
  echo "=== unified diff (A -> B) ==="
  printf '%s\n' "$CHG" | while read -r f; do
    diff -u --label "A/$f" --label "B/$f" "$A/$f" "$B/$f" || true
  done
fi

echo
[ "$TOTAL" -eq 0 ] && { echo "RESULT: identical"; exit 0; }
echo "RESULT: $TOTAL file(s) differ"; exit 1