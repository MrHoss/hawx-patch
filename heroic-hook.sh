#!/usr/bin/env bash
# Pre-launch hook do Heroic: reaplica o patch do H.A.W.X. antes de cada execucao.
# Util depois de reinstalar o jogo, que restaura os shaders originais.
#
# Aponte o Heroic para este arquivo em "beforeLaunchScriptPath" (por prefixo).
# Ajuste GAME_DIR abaixo para a sua maquina, ou exporte HAXW_GAME_DIR.
#
# Diferente de chamar apply.sh direto, este hook:
#   - fixa o prefixo, para nao patchear o jogo errado quando ha varios
#     instalados (a autodetecao do apply.sh pega o primeiro em ordem alfabetica)
#   - falha alto se algo ficar pendente, em vez de continuar em silencio
#   - loga em $HAWX_FIX_LOG (padrao /tmp/hawx-fix.log)
#
# O patch em si e o mesmo do repositorio: o hook so o orquestra.
set -uo pipefail

# Nao usar `export VAR="${VAR:-x}"`: sob `set -u` o export nao registra a
# variavel e o uso seguinte aborta com "variavel nao associada".
LOG="${HAWX_FIX_LOG:-/tmp/hawx-fix.log}"
PATCH_DIR="${HAWX_PATCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

msg() { printf '[hawx] %s\n' "$1" | tee -a "$LOG"; }

GAME_DIR="${1:-${HAWX_GAME_DIR:-/home/daniel/Games/Heroic/Prefixes/default/Tom Clancys H.A.W.X./drive_c/Program Files (x86)/DODI-Repacks/Tom Clancys H A W X}}"

msg "inicio"
msg "prefixo: $GAME_DIR"

if [ ! -x "$PATCH_DIR/apply.sh" ]; then
  msg "ERRO: apply.sh nao encontrado em $PATCH_DIR (ajuste HAXW_PATCH_DIR)"
  exit 1
fi

OUT=$("$PATCH_DIR/apply.sh" --with-depthms "$GAME_DIR" 2>&1)
rc=$?
printf '%s\n' "$OUT" >>"$LOG"
if [ $rc -ne 0 ]; then
  msg "ERRO: patch nao ficou completo (rc=$rc) -- ver $LOG"
  exit 1
fi
msg "patch ok"

# Tela cheia na resolucao do monitor. O modo 1280x720 existe no XWayland e
# funciona; a preferencia aqui e so pelo tamanho nativo.
#
# As settings nao ficam na pasta do jogo, e sim em
# <prefixo>/drive_c/users/<usuario>/... -- e o usuario do prefixo nem sempre e
# o do sistema (o antigo e' steamuser, nao daniel). Por isso busca em vez de
# caminho fixo.
case "$GAME_DIR" in
  */drive_c/*) PREFIX="${GAME_DIR%%/drive_c/*}" ;;
  *)           PREFIX="$GAME_DIR" ;;
esac

found=0
while IFS= read -r ini; do
  found=1
  sed -i 's/^windowed = .*/windowed = false\r/; s/^width = .*/width = 1920\r/; s/^height = .*/height = 1080\r/' "$ini" 2>/dev/null
  msg "settings: $ini"
done < <(find "$PREFIX" -path '*Profiles/_settings_*.ini' 2>/dev/null)
[ $found -eq 1 ] || msg "aviso: nenhum _settings_*.ini encontrado sob $PREFIX"

msg "fim"
exit 0