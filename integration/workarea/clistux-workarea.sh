#!/usr/bin/env bash
# clistux: デスクトップの作業領域(画面からパネル・ドックを除いた範囲)を X11 に知らせる。
#
# COSMIC は _NET_WORKAREA / _GTK_WORKAREAS_D0 を設定しないので、Wine は画面全体を使えると考える。
# CSP は自分で枠を描き、ウィンドウマネージャが最大化した大きさが自分の考える作業領域と合わないと、
# 元の大きさに戻してしまう。clistux-workarea.py で作業領域を測り、winex11 が読む
# _GTK_WORKAREAS_D0 としてルートウィンドウに設定する。
#
# 起動スクリプトから WINEPREFIX と WINESERVER を受け取って呼ばれる。起動を失敗させることはしない。
# 作者の以前の実装(COSMIC 向けの修正、2026-11)を、常駐の wineserver を使わない形に簡単にしたもの。

[[ "${XDG_CURRENT_DESKTOP:-}" == *COSMIC* ]] || exit 0
[[ "${CLISTUX_WORKAREA:-1}" == 0 ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v xprop >/dev/null 2>&1 || exit 0

# ウィンドウマネージャが自分で知らせている
xprop -root _NET_WORKAREA 2>/dev/null | grep -q '=' && exit 0

probe="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/clistux-workarea.py"
[[ -f "$probe" ]] || exit 0

new=$(timeout 10 python3 -I "$probe" 2>/dev/null) || exit 0
[[ "$new" =~ ^[0-9]+(,\ [0-9]+)*$ ]] || exit 0
old=$(xprop -root _GTK_WORKAREAS_D0 2>/dev/null | sed -n 's/^[^=]*= //p')
[[ "$new" == "$old" ]] && exit 0

xprop -root -f _GTK_WORKAREAS_D0 32c -set _GTK_WORKAREAS_D0 "$new" || exit 0

# Wine は画面の配置を覚えている。CSP・CLIP STUDIO が動いていなければ、wineserver を止めて新しい作業領域を読ませる。
if ! pgrep -u "$(id -u)" -f 'CLIPStudio[A-Za-z]*\.exe' >/dev/null 2>&1 && [[ -n "${WINESERVER:-}" ]]; then
    "$WINESERVER" -k 2>/dev/null || true
    "$WINESERVER" -w 2>/dev/null || true
fi
exit 0
