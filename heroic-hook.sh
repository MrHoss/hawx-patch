#!/usr/bin/env bash
# Pre-launch hook do Heroic: reaplica o patch do H.A.W.X. antes de cada execucao.
# Util depois de reinstalar o jogo, que restaura os shaders originais.
#
# Aponte o Heroic para este arquivo em "beforeLaunchScriptPath" (por prefixo).
# Ele resolve o prefixo do jogo por HAXW_GAME_DIR; ajuste esse valor (ou a
# variavel GAME_DIR) para a sua maquina -- ver README.md.
#
# Diferente de chamar apply.sh direto, este hook:
#   - fixa o prefixo, para nao patchear o jogo errado quando ha varios instalados
#     (a autodetecao do apply.sh pega o primeiro em ordem alfabetica)
#   - falha alto se algo ficar pendente, em vez de continuar em silencio
#   - loga em $HAWX_FIX_LOG (padrao /tmp/hawx-fix.log)
#
# O patch em si e o mesmo do repositorio: o hook so o orquestra.
set -uo pipefail

LOG="${HAWX_FIX_LOG:-/tmp/hawx-fix.log}"