#!/usr/bin/env bash
# Installs the Tom Clancy's H.A.W.X. HLSL fixes needed to run under wined3d.
#
#   ./install.sh /path/to/the/game
#   ./install.sh --no-depthms /path/to/the/game
#   ./install.sh --revert /path/to/the/game
#
# "The game folder" is the one that contains Data/Shaders_PC. Usually:
#
#   .../Tom Clancys H A W X/                                (Steam, GOG, ...)
#   .../drive_c/Program Files (x86)/.../Tom Clancys H A W X/   (Wine prefix)
#
# If you are not sure which one it is, look for it with:
#   find ~ -type d -name Shaders_PC -path '*/Data/*' 2>/dev/null
#
# Alternatively, copy install.sh and patches/ into the game folder and run it
# with no arguments: it locates itself.
#
# Idempotent: running it again changes nothing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="$HERE/patches/hawx-wined3d-shader-fix.patch"
DEPTH="$HERE/patches/hawx-wined3d-depthms-workaround.patch"

GAME=""
DEPTHMS=1
REVERT=0
for a in "$@"; do
  case "$a" in
    --no-depthms) DEPTHMS=0 ;;
    --revert)     REVERT=1 ;;
    -h|--help)    awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)           echo "unknown option: $a" >&2; exit 2 ;;
    *)            GAME="$a" ;;
  esac
done

# --- locate Data/Shaders_PC ---------------------------------------------
# Accepts the game folder, the Shaders_PC folder itself, or nothing (in which
# case the script's own location is used).
if [ -n "$GAME" ]; then
  if   [ -d "$GAME/Data/Shaders_PC" ]; then
    SP="$GAME/Data/Shaders_PC"
  elif [ "$(basename "$GAME")" = Shaders_PC ] && [ -d "$GAME" ]; then
    SP="$GAME"
  else
    echo "Could not find Data/Shaders_PC in: $GAME" >&2
    echo "The game folder must contain Data/Shaders_PC (see --help)." >&2
    exit 1
  fi
else
  SP=""
  for base in "$HERE" "$HERE/.." "$HERE/../.."; do
    if   [ -d "$base/Data/Shaders_PC" ]; then
      SP="$base/Data/Shaders_PC"; break
    elif [ "$(basename "$base")" = Shaders_PC ] && [ -d "$base" ]; then
      SP="$base"; break
    fi
  done
  if [ -z "$SP" ]; then
    cat >&2 <<EOF
Could not find Data/Shaders_PC.

Pass the game folder:
  $0 /path/to/the/game

or copy install.sh and patches/ into the game folder and run it with no arguments.
EOF
    exit 1
  fi
fi
SP="$(cd "$SP" && pwd)"
ROOT="$(dirname "$(dirname "$SP")")"
echo "Game: $ROOT"

# --- one-time backup ----------------------------------------------------
BK="$ROOT/Data/Shaders_PC.hawxbackup"
if [ ! -d "$BK" ]; then
  cp -a "$SP" "$BK"
  echo "Backup created: $BK"
fi

cd "$ROOT"

apply() {  # apply <patch> [extra-flags...]
  local f="$1"; shift
  # "$@" is deliberately unquoted: with an empty list patch must receive no
  # argument at all. Passing "" (quoted) makes patch take an empty filename
  # and fail, which would report "already applied" on an untouched tree.
  if patch -p1 "$@" --forward --batch --silent --no-backup-if-mismatch \
       --reject-file=- < "$f" >/dev/null 2>&1
  then echo "  applied: $(basename "$f")"
  else echo "  already applied: $(basename "$f")"
  fi
}

if [ "$REVERT" = 1 ]; then
  apply "$MAIN" -R
  [ "$DEPTHMS" = 1 ] && apply "$DEPTH" -R
else
  apply "$MAIN"
  [ "$DEPTHMS" = 1 ] && apply "$DEPTH"
fi

# --- verification --------------------------------------------------------
# `patch --forward` also reports "already applied" when the context does not
# match because the tree was only PARTIALLY fixed. Without this check the
# script silently delivers half the patch. After applying, the reverse patch
# must succeed; after reverting, the forward patch must succeed.
echo
failures=0
total=0
for p in "$MAIN" "$DEPTH"; do
  [ "$p" = "$DEPTH" ] && [ "$DEPTHMS" = 0 ] && continue
  total=$((total + 1))
  name=$(basename "$p")
  if [ "$REVERT" = 1 ]; then rev=""; state="reverted"
  else rev="-R"; state="applied"; fi
  # shellcheck disable=SC2086
  if patch -p1 $rev --dry-run --batch --silent --reject-file=- < "$p" >/dev/null 2>&1; then
    echo "  ok: $name $state"
  else
    echo "  FAILED: $name is not complete."
    echo "         The tree was probably already partially fixed."
    echo "         To start over from the backup:"
    echo "           rm -rf Data/Shaders_PC && cp -a Data/Shaders_PC.hawxbackup Data/Shaders_PC"
    failures=$((failures + 1))
  fi
done

echo
echo "Backup kept at: $BK"
if [ "$failures" -gt 0 ]; then
  echo "RESULT: INCOMPLETE ($failures of $total)"
  exit 1
fi
if [ "$REVERT" = 1 ]; then
  echo "RESULT: reverted (to get the originals back, restore from the backup)"
else
  echo "RESULT: complete"
fi
exit 0