#!/usr/bin/env bash
# manifest.sh -- list with sha256 of the whole shader tree (.fx and .h).
# Useful as a reference to diff between prefixes / between patch versions.
#
#   ./manifest.sh <dir_Shaders_PC> [output_file]
set -uo pipefail

DIR="${1:?pass the Data/Shaders_PC directory}"
OUT="${2:-/tmp/hawx-manifest.txt}"
[ -d "$DIR" ] || { echo "no such directory: $DIR" >&2; exit 1; }

DIR="$(cd "$DIR" && pwd)"
( cd "$DIR" && find . -type f \( -name '*.fx' -o -name '*.h' \) -print0 \
  | xargs -0 sha256sum | LC_ALL=C sort -k2 ) > "$OUT"

n=$(wc -l < "$OUT")
echo "  $n files  ->  $OUT"
echo "  root: $DIR"