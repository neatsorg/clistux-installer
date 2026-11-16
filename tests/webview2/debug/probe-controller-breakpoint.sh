#!/usr/bin/env bash
# 試験プログラムで、ブレークポイントが CreateCoreWebView2Controller で止まるかを確かめる
set -u
# 出力: ~/.local/share/clistux-test/bp-*.txt。オフセットは WebView2 ランタイム 135.0.3179.85 の EmbeddedBrowserWebView.dll のもの(wv2probe が書き出す)
T=~/.local/share/clistux-test; W=$T/wine-11.4/bin
export WINEPREFIX=$T/prefix WINESERVER=$W/wineserver WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d"
cd ~/project/clistux/tests/webview2
WV2PROBE_DELAY_MS=8000 WINEDEBUG=-all,+loaddll nohup $W/wine wv2probe.exe hwnd 25 > $T/bp-probe-load.log 2>&1 &
for i in $(seq 80); do grep -q 'EmbeddedBrowserWebView.dll" at' $T/bp-probe-load.log && break; sleep 0.25; done
BASE=$(grep -oE 'EmbeddedBrowserWebView.dll" at [0-9A-F]+' $T/bp-probe-load.log | awk '{print $3}')
P=$(WINEDEBUG=-all $W/wine tasklist 2>/dev/null | awk '/wv2probe/{print $2}')
echo "EBWebView base 0x$BASE, pid $P"
{
    printf 'break *0x%x\n' $((0x$BASE + 0x687f0))
    echo cont
    for k in $(seq 15); do sleep 1; printf 'bt 4\ncont\n'; done
    echo detach; echo quit
} | WINEDEBUG=-all timeout 60 $W/winedbg $P > $T/bp-probe.txt 2>&1
WINEDEBUG=-all $W/wineserver -k
