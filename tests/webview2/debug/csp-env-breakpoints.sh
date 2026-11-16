#!/usr/bin/env bash
# CSP を起動し、WebView2 の DLL が読み込まれたら winedbg をつないで、Environment のメソッドにブレークポイントを置く
set -u
# 出力: ~/.local/share/clistux-test/bp-*.txt。オフセットは WebView2 ランタイム 135.0.3179.85 の EmbeddedBrowserWebView.dll のもの(wv2probe が書き出す)
T=~/.local/share/clistux-test; W=$T/wine-11.4/bin
export WINEPREFIX=$T/prefix WINESERVER=$W/wineserver WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d"
WINEDEBUG=-all,+loaddll nohup $W/wine "C:\\Program Files\\CELSYS\\CLIP STUDIO 1.5\\CLIP STUDIO PAINT\\CLIPStudioPaint.exe" > $T/bp-load.log 2>&1 &
for i in $(seq 80); do grep -q 'EmbeddedBrowserWebView.dll" at' $T/bp-load.log && break; sleep 0.25; done
BASE=$(grep -oE 'EmbeddedBrowserWebView.dll" at [0-9A-F]+' $T/bp-load.log | awk '{print $3}')
P=$(WINEDEBUG=-all $W/wine tasklist 2>/dev/null | awk '/CLIPStudioPaint/{print $2}')
echo "EBWebView base 0x$BASE, pid $P"
OFFS=(687f0 69760 688d0 6a5e0 6a6c0 68cd0 68ed0 68850 69640 6ab40 6ac30 6ce20 68af0 6c660 6c790 6c870 6b8f0 6bbc0 6bc50 6c2c0 6d0b0)
{
    idx=3
    for o in "${OFFS[@]}"; do printf 'break *0x%x\n' $((0x$BASE + 0x$o)); idx=$((idx+1)); done
    echo cont
    for k in $(seq 30); do sleep 1; printf 'bt 6\ncont\n'; done
    echo detach; echo quit
} | WINEDEBUG=-all timeout 90 $W/winedbg $P > $T/bp-env.txt 2>&1
WINEDEBUG=-all $W/wineserver -k
