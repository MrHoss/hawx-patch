#!/usr/bin/env bash
# Aplica os patches HLSL do H.A.W.X. para rodar sob wined3d/vkd3d.
#
#   ./apply.sh                 # detecta o jogo e aplica o patch principal
#   ./apply.sh /caminho/do/jogo # caminho explicito
#   ./apply.sh --with-depthms  # aplica tambem o workaround de DepthMS*
#   ./apply.sh --revert        # desfaz
#
# Idempotente: rodar de novo nao muda nada (usa patch --forward).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="$HERE/patches/hawx-wined3d-shader-fix.patch"
DEPTH="$HERE/patches/hawx-wined3d-depthms-workaround.patch"

GAME=""
WITH_DEPTH=0
REVERT=0
for a in "$@"; do
  case "$a" in
    --with-depthms) WITH_DEPTH=1 ;;
    --revert)       REVERT=1 ;;
    -*)             echo "opcao desconhecida: $a" >&2; exit 2 ;;
    *)              GAME="$a" ;;
  esac
done

# --- localiza o jogo -------------------------------------------------------
# Aceita a raiz do jogo (que contem Data/Shaders_PC) ou o proprio Shaders_PC.
if [ -n "$GAME" ] && [ -d "$GAME/Data/Shaders_PC" ]; then
  SP="$GAME/Data/Shaders_PC"
elif [ -n "$GAME" ] && [ "$(basename "$GAME")" = Shaders_PC ]; then
  SP="$GAME"
else
  SP=""
  while IFS= read -r f; do SP="$f"; break; done < <(
    find "$HOME/Games" -type d -path '*/Data/Shaders_PC' 2>/dev/null | sort)
fi
if [ -z "$SP" ] || [ ! -d "$SP" ]; then
  echo "Nao encontrei Data/Shaders_PC. Use: $0 /caminho/do/jogo" >&2
  exit 1
fi

ROOT="$(dirname "$(dirname "$SP")")"   # .../<jogo>
echo "Jogo: $ROOT"

# --- backup unico ----------------------------------------------------------
BK="$ROOT/Data/Shaders_PC.hawxbackup"
if [ ! -d "$BK" ]; then
  cp -a "$SP" "$BK"
  echo "Backup criado: $BK"
fi

cd "$ROOT"

run() {
  local f="$1" dir
  dir="$(basename "$f")"
  if [ "$REVERT" = 1 ]; then
    if patch -p1 -R --forward --batch --silent --reject-file=- < "$f" >/dev/null 2>&1; then
      echo "  revertido: $dir"
    else
      echo "  ja estava revertido: $dir"
    fi
  else
    if patch -p1 --forward --batch --silent --reject-file=- < "$f" >/dev/null 2>&1; then
      echo "  aplicado: $dir"
    else
      echo "  ja estava aplicado: $dir"
    fi
  fi
}

run "$MAIN"
[ "$WITH_DEPTH" = 1 ] && run "$DEPTH"

echo "Pronto. Backup intacto em: $BK"
[ "$REVERT" = 1 ] && echo "Para desfazer de vez, apague os shaders e restaure do backup."
exit 0