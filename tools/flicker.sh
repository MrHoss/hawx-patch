#!/usr/bin/env bash
# flicker.sh -- mede a cintilacao da tela do jogo.
#
# A sessao e Wayland, entao o root do XWayland e preto: capturar a tela inteira
# nao serve. Capturamos direto a janela do jogo (xprop -> import -window).
#
#   ./flicker.sh <segundos> <saida.csv>
#
# Notas de robustez: o jogo vive ~50s e pode fechar a janela no meio da medicao,
# e o import trava se a janela sumir. Da�� o timeout em cada captura e a
# redescoberta periodica da janela.
set -uo pipefail
cd "$(dirname "$0")"

SECS="${1:-30}"
OUT="${2:-/tmp/flicker.csv}"
TMPPNG=/tmp/.flicker.png
CSV=/tmp/flicker_raw.csv

find_window() {
  xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+' | while read -r w; do
    case "$(xprop -id "$w" WM_CLASS 2>/dev/null)" in
      *steam_proton*|*HAWX*) echo "$w"; break ;;
    esac
  done
}

grab() {  # imprime brilho medio, ou nada se falhar
  rm -f "$TMPPNG"
  timeout 6 import -window "$1" -silent "$TMPPNG" 2>/dev/null || return 1
  [ -s "$TMPPNG" ] || return 1
  timeout 6 python3 ymean.py < "$TMPPNG" 2>/dev/null
}

WIN=$(find_window)
[ -n "$WIN" ] || { echo "janela do jogo nao encontrada (rode o jogo primeiro)" >&2; exit 1; }
echo "janela do jogo: $WIN"

: > "$CSV"
t0=$(date +%s.%N)
n=0; miss=0
while :; do
  now=$(date +%s.%N)
  el=$(awk "BEGIN{printf \"%.3f\", $now-$t0}")
  [ "$el" -ge "$SECS" ] && break
  if [ -z "$WIN" ] || [ $((n % 10)) -eq 0 ]; then
    W2=$(find_window); [ -n "$W2" ] && WIN="$W2"
  fi
  [ -n "$WIN" ] || { echo "  janela sumiu em ${el}s"; break; }
  v=$(grab "$WIN")
  if [ -n "$v" ]; then echo "$el $v" >> "$CSV"; miss=0; else miss=$((miss+1)); fi
  n=$((n+1))
  [ "$miss" -ge 3 ] && { echo "  3 capturas falharam em ${el}s (jogo provavelmente fechou)"; break; }
done
rm -f "$TMPPNG"

[ -s "$CSV" ] || { echo "  nenhum frame capturado"; exit 1; }
cp "$CSV" "$OUT"
echo "frames: $(wc -l < "$OUT") em ${SECS}s  ->  $OUT"
awk '{a[NR]=$2} END{
  n=NR; if(n<3){ print "  amostra insuficiente"; exit }
  s=0; mn=a[1]; mx=a[1];
  for(i=1;i<=n;i++){ s+=a[i]; if(a[i]<mn)mn=a[i]; if(a[i]>mx)mx=a[i] }
  m=s/n; v=0; d=0; k=0;
  for(i=1;i<=n;i++){ x=a[i]-m; v+=x*x;
    if(i>1){ y=a[i]-a[i-1]; if(y<0)y=-y; if(y>d)d=y; if(y>1.0)k++ } }
  printf "  Ymedio=%.2f  min=%.2f  max=%.2f  amplitude=%.2f\n", m, mn, mx, mx-mn;
  printf "  desvio=%.3f  maior salto=%.2f  transicoes(>1.0)=%d/%d (%.0f%%)\n", sqrt(v/n), d, k, n-1, 100*k/(n-1);
}' "$OUT"
echo -n "  serie (t:Y): "
awk '{printf "%s%.1f@%ds ", (NR%4==1?"\n    ":""), $2, int($1)}' "$OUT"; echo