#!/usr/bin/env bash
# Instala as correcoes HLSL do Tom Clancy's H.A.W.X. para rodar sob wined3d.
#
#   ./install.sh /caminho/para/o/jogo
#   ./install.sh --no-depthms /caminho/para/o/jogo
#   ./install.sh --revert /caminho/para/o/jogo
#
# "Pasta do jogo" e a que contem Data/Shaders_PC. Normalmente:
#
#   .../Tom Clancys H A W X/                                (Steam, GOG, ...)
#   .../drive_c/Program Files (x86)/.../Tom Clancys H A W X/   (prefixo Wine)
#
# Se nao souber qual e, procure com:
#   find ~ -type d -name Shaders_PC -path '*/Data/*' 2>/dev/null
#
# Se preferir, copie install.sh e patches/ para dentro da pasta do jogo e rode
# sem argumentos: ele se localiza sozinho.
#
# Idempotente: rodar de novo nao muda nada.
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
    -*)           echo "opcao desconhecida: $a" >&2; exit 2 ;;
    *)            GAME="$a" ;;
  esac
done

# --- localiza Data/Shaders_PC ----------------------------------------------
# Aceita a pasta do jogo, o proprio Shaders_PC, ou nada (usando a propria
# localizacao do script).
if [ -n "$GAME" ]; then
  if   [ -d "$GAME/Data/Shaders_PC" ]; then
    SP="$GAME/Data/Shaders_PC"
  elif [ "$(basename "$GAME")" = Shaders_PC ] && [ -d "$GAME" ]; then
    SP="$GAME"
  else
    echo "Nao achei Data/Shaders_PC em: $GAME" >&2
    echo "A pasta do jogo deve conter Data/Shaders_PC (veja --help)." >&2
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
Nao achei Data/Shaders_PC.

Informe a pasta do jogo:
  $0 /caminho/para/o/jogo

ou copie install.sh e patches/ para dentro da pasta do jogo e rode sem argumentos.
EOF
    exit 1
  fi
fi
SP="$(cd "$SP" && pwd)"
ROOT="$(dirname "$(dirname "$SP")")"
echo "Jogo: $ROOT"

# --- backup unico ----------------------------------------------------------
BK="$ROOT/Data/Shaders_PC.hawxbackup"
if [ ! -d "$BK" ]; then
  cp -a "$SP" "$BK"
  echo "Backup criado: $BK"
fi

cd "$ROOT"

apply() {  # apply <patch> [extra-flags...]
  local f="$1"; shift
  # `"$@"` sem aspas de proposito: com lista vazia o patch nao recebe argumento
  # nenhum. Passar "" (aspas) faria o patch tomar um nome de arquivo vazio e
  # falhar, relatando "ja estava aplicado" numa arvore intocada.
  if patch -p1 "$@" --forward --batch --silent --no-backup-if-mismatch \
       --reject-file=- < "$f" >/dev/null 2>&1
  then echo "  aplicado: $(basename "$f")"
  else echo "  ja estava aplicado: $(basename "$f")"
  fi
}

if [ "$REVERT" = 1 ]; then
  apply "$MAIN" -R
  [ "$DEPTHMS" = 1 ] && apply "$DEPTH" -R
else
  apply "$MAIN"
  [ "$DEPTHMS" = 1 ] && apply "$DEPTH"
fi

# --- verificacao ------------------------------------------------------------
# `patch --forward` diz "ja estava aplicado" tambem quando o contexto nao bate
# porque a arvore ja estava PARCIALmente corrigida. Sem esta checagem o script
# entrega metade do patch em silencio. Apos aplicar, o patch reverso tem de
# funcionar; apos reverter, o patch normal tem de funcionar.
echo
falhas=0
total=0
for p in "$MAIN" "$DEPTH"; do
  [ "$p" = "$DEPTH" ] && [ "$DEPTHMS" = 0 ] && continue
  total=$((total + 1))
  nome=$(basename "$p")
  if [ "$REVERT" = 1 ]; then rev=""; estado="revertido"
  else rev="-R"; estado="aplicado"; fi
  # shellcheck disable=SC2086
  if patch -p1 $rev --dry-run --batch --silent --reject-file=- < "$p" >/dev/null 2>&1; then
    echo "  ok: $nome $estado"
  else
    echo "  FALHOU: $nome nao ficou completo."
    echo "         A arvore provavelmente ja estava parcialmente corrigida."
    echo "         Para recomecar do zero, a partir do backup:"
    echo "           rm -rf Data/Shaders_PC && cp -a Data/Shaders_PC.hawxbackup Data/Shaders_PC"
    falhas=$((falhas + 1))
  fi
done

echo
echo "Backup intacto em: $BK"
if [ "$falhas" -gt 0 ]; then
  echo "RESULTADO: INCOMPLETO ($falhas de $total)"
  exit 1
fi
if [ "$REVERT" = 1 ]; then
  echo "RESULTADO: revertido (para voltar ao original, restaure do backup)"
else
  echo "RESULTADO: completo"
fi
exit 0