#!/usr/bin/env bash
# manifest.sh -- lista com sha256 de toda a arvore de shaders (.fx e .h).
# Serve de referencia para diff entre prefixos / entre versoes do patch.
#
#   ./manifest.sh <dir_Shaders_PC> [arquivo_saida]
set -uo pipefail

DIR="${1:?informe o dir Data/Shaders_PC}"
OUT="${2:-/tmp/hawx-manifest.txt}"
[ -d "$DIR" ] || { echo "dir inexistente: $DIR" >&2; exit 1; }

DIR="$(cd "$DIR" && pwd)"
( cd "$DIR" && find . -type f \( -name '*.fx' -o -name '*.h' \) -print0 \
  | xargs -0 sha256sum | LC_ALL=C sort -k2 ) > "$OUT"

n=$(wc -l < "$OUT")
echo "  $n arquivos  ->  $OUT"
echo "  raiz: $DIR"