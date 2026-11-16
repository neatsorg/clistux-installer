#!/usr/bin/env bash
# Windows のフォント(~/.local/share/fonts)が無い環境を再現して CSP を起動し、
# ウィンドウが出るまでの秒数・選ばれたフォント・画面を記録する。
#
# 使い方: tests/fonts/nofont-run.sh <名前> [出力先]
#   HOME と XDG_* を空のフォルダーに向けるので、fontconfig はユーザーのフォントを見ない。
#   前提: プレフィックスのレジストリから、ユーザーのフォントを指す行を消しておくこと
#   (strip-user-fonts.py)。Wine のコマンドは、補助のものも含めてすべてこの環境で実行する。
set -u
NAME="${1:?名前を指定してください}"
OUT="${2:-${XDG_RUNTIME_DIR:-/tmp}/clistux-nofont}"
T="${CLISTUX_TEST:-$HOME/.local/share/clistux-test}"
W="$T/wine-11.4/bin"
REAL_HOME="$HOME"
FAKE="$OUT/fakehome"
mkdir -p "$OUT" "$FAKE/.local/share" "$FAKE/.cache" "$FAKE/.config"

export HOME="$FAKE" XDG_DATA_HOME="$FAKE/.local/share" XDG_CACHE_HOME="$FAKE/.cache" XDG_CONFIG_HOME="$FAKE/.config"
export WINEPREFIX="$T/prefix" WINESERVER="$W/wineserver" WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d"

if fc-list | grep -q "$REAL_HOME/.local/share/fonts"; then
    echo "エラー: ユーザーのフォントが見えています" >&2; exit 1
fi

WINEDEBUG=-all "$W/wineserver" -k; sleep 2
start=$(date +%s)
WINEDEBUG=-all,trace+font nohup "$W/wine" "C:\\Program Files\\CELSYS\\CLIP STUDIO 1.5\\CLIP STUDIO PAINT\\CLIPStudioPaint.exe" 2>&1 \
    | grep --line-buffered 'Chosen' > "$OUT/$NAME.log" &
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
