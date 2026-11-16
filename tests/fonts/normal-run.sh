#!/usr/bin/env bash
# ふだんの環境(ユーザーのフォントも見える)で CSP を起動して撮影する。nofont-run.sh と比べるため。
# 使い方: tests/fonts/normal-run.sh <名前> [出力先]
set -u
NAME="${1:?名前を指定してください}"
OUT="${2:-${XDG_RUNTIME_DIR:-/tmp}/clistux-nofont}"
T="${CLISTUX_TEST:-$HOME/.local/share/clistux-test}"
W="$T/wine-11.4/bin"
mkdir -p "$OUT"
export WINEPREFIX="$T/prefix" WINESERVER="$W/wineserver" WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d"
WINEDEBUG=-all "$W/wineserver" -k; sleep 2
start=$(date +%s)
WINEDEBUG=-all nohup "$W/wine" "C:\\Program Files\\CELSYS\\CLIP STUDIO 1.5\\CLIP STUDIO PAINT\\CLIPStudioPaint.exe" >/dev/null 2>&1 &
w=
for _ in $(seq 240); do
    for x in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+'); do
        xprop -id "$x" WM_NAME 2>/dev/null | grep -q 'CLIP STUDIO PAINT' && { w=$x; break; }
    done
    [ -n "$w" ] && break; sleep 1
done
[ -z "$w" ] && { echo "$NAME: 240 秒以内にウィンドウが出ませんでした"; exit 1; }
echo "$NAME: ウィンドウまで $(( $(date +%s) - start )) 秒"
sleep 20
import -window "$w" "$OUT/$NAME.png" 2>/dev/null && echo "撮影: $OUT/$NAME.png"
