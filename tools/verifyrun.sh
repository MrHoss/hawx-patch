#!/usr/bin/env bash
# verifyrun.sh -- roda o jogo em um prefixo/proton e relata o estado, SEM tocar
# nos shaders. Serve para validar um prefixo novo e para comparar Protons.
#
#   ./verifyrun.sh --gamedir <raiz_do_jogo> --proton <dir_proton> --label <nome>
#                  [--secs 70] [--flick 18-45] [--fs]
#
#   --fs    fora tela cheia 1920x1080 no _settings_*.ini do prefixo (o 1280x720
#           do jogo nao existe no XWayland: o xrandr da BadMatch e a tela fica preta)
#
# Exit: 0 sempre (e um relatorio, nao um teste de pass/fail).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GAMEDIR=""; PROTON=""; LABEL="run"; SECS=70; FLICK=""; DOFS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --gamedir) GAMEDIR="${2:?}"; shift 2 ;;
    --proton)  PROTON="${2:?}";  shift 2 ;;
    --label)   LABEL="${2:?}";   shift 2 ;;
    --secs)    SECS="${2:?}";    shift 2 ;;
    --flick)   FLICK="${2:?}";   shift 2 ;;
    --fs)      DOFS=1;           shift ;;
    *) echo "opcao desconhecida: $1" >&2; exit 2 ;;
  esac
done
[ -n "$GAMEDIR" ] && [ -n "$PROTON" ] || { echo "falta --gamedir/--proton" >&2; exit 2; }
[ -d "$GAMEDIR" ] || { echo "gamedir inexistente: $GAMEDIR" >&2; exit 2; }
[ -x "$PROTON/proton" ] || { echo "sem executavel proton em: $PROTON" >&2; exit 2; }
SP="$GAMEDIR/Data/Shaders_PC"

GAMEDIR="$(cd "$GAMEDIR" && pwd)"
echo "##### $LABEL"
echo "  jogo:   $GAMEDIR"
echo "  proton: $PROTON"
echo "  shaders: $(find "$SP" -name '*.fx' 2>/dev/null | wc -l) .fx" \
     "| DepthMS originais=$(grep -l Texture2DMS "$SP"/DepthMS*ToLinDepth_PS.fx 2>/dev/null | wc -l)"

PVER=$(tr -d '\n' < "$PROTON/version" 2>/dev/null | grep -oE '[0-9]{9,}' | head -1)
echo "  proton version: ${PVER:-desconhecida}"

# prefixo = o diretorio pai da raiz do jogo, ou a propria raiz se ja for prefixo
PREFIX=$(dirname "$(dirname "$(dirname "$(dirname "$GAMEDIR")")")")
if [ -d "$PREFIX/drive_c" ] || [ -f "$PREFIX/system.reg" ]; then :; else PREFIX=$(dirname "$GAMEDIR"); fi
echo "  prefixo: $PREFIX"

if [ "$DOFS" = 1 ]; then
  for s in "$PREFIX"/drive_c/users/*/Documents/*/Profiles/_settings_*.ini; do
    [ -f "$s" ] || continue
    sed -i 's/^windowed = .*/windowed = false\r/;s/^width = .*/width = 1920\r/;s/^height = .*/height = 1080\r/' "$s" 2>/dev/null
    echo "  video forcado: 1920x1080 tela cheia  ($(basename "$s"))"
  done
fi

pkill -x HAWX.exe 2>/dev/null; pkill -x wineserver 2>/dev/null; sleep 2

export WINEPREFIX="$PREFIX" STEAM_COMPAT_DATA_PATH="$PREFIX" \
  STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/daniel/.local/share/Steam \
  PROTON_USE_WINED3D=1 WINEDEBUG=fixme-all
LOG="/tmp/verifyrun_${LABEL}.log"
setsid "$PROTON/proton" run "$GAMEDIR/HAWX.exe" >"$LOG" 2>&1 </dev/null &
PWRAP=$!
for i in $(seq 1 100); do
  pgrep -x HAWX.exe >/dev/null && break
  kill -0 "$PWRAP" 2>/dev/null || break
  sleep 0.3
done

if ! pgrep -x HAWX.exe >/dev/null; then
  echo "  RESULTADO: o jogo nem chegou a abrir"
  tail -12 "$LOG" | sed 's/^/    | /'
  exit 0
fi
QPID=$(pgrep -x HAWX.exe | head -1)
echo "  janela/processo: PID $QPID"

if [ -n "$FLICK" ]; then
  t1="${FLICK%%-*}"; t2="${FLICK##*-}"
  sleep "$t1"
  "$HERE/flicker.sh" "$((t2-t1))" "/tmp/flick_${LABEL}.csv" 2>&1 | sed 's/^/  /'
  QPID=$(pgrep -x HAWX.exe | head -1)
fi

died=""
if [ -n "$QPID" ]; then
  for k in $(seq 1 "$SECS"); do
    sleep 1
    kill -0 "$QPID" 2>/dev/null || { died=$k; break; }
  done
fi
if [ -n "$died" ]; then echo "  SOBREVIVENCIA: morreu em ${died}s"
else echo "  SOBREVIVENCIA: rodou os ${SECS}s (cpu=$(ps -o pcpu= -p "$QPID" 2>/dev/null | tr -d ' ')% | janelas=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -coE '0x[0-9a-f]+'))"; fi

pkill -x HAWX.exe 2>/dev/null; sleep 1; pkill -x wineserver 2>/dev/null

echo "  --- erros de shader (E*) ---"
ERRS=$(grep -oE '\S*\.fx:[0-9]+:[0-9]+: E[0-9]+: [^\r]*|<anonymous>:[0-9]+:[0-9]+: E[0-9]+: [^\r]*' "$LOG" | sort -u | sed 's|Data/Shaders_PC/||')
if [ -n "$ERRS" ]; then printf '%s\n' "$ERRS" | sed 's/^/    /'; else echo "    (nenhum)"; fi
echo "  total de linhas E*: $(grep -cE ': E[0-9]+:' "$LOG")"
echo "  log: $LOG"
echo