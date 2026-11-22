#!/usr/bin/env bash
# clistux: デスクトップの作業領域(画面からパネル・ドックを除いた範囲)を X11 に知らせる。
#
# COSMIC と Hyprland は _NET_WORKAREA / _GTK_WORKAREAS_D0 を設定しないので、Wine は画面全体を使えると考える。
# CSP は自分で枠を描き、ウィンドウマネージャが最大化した大きさが自分の考える作業領域と合わないと、
# 元の大きさに戻してしまう。作業領域を求め(COSMIC は clistux-workarea.py で測り、Hyprland は hyprctl の値から clistux-workarea-hyprland.py で計算する)、
# winex11 が読む _GTK_WORKAREAS_D0 としてルートウィンドウに設定する。
#
# 起動スクリプトから WINEPREFIX と WINESERVER を受け取って呼ばれる。起動を失敗させることはしない。
# 作者の以前の実装(COSMIC 向けの修正、2026-11)を、常駐の wineserver を使わない形に簡単にしたもの。

[[ "${CLISTUX_WORKAREA:-1}" == 0 ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v xprop >/dev/null 2>&1 || exit 0

# ウィンドウマネージャが自分で知らせている
xprop -root _NET_WORKAREA 2>/dev/null | grep -q '=' && exit 0

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1; then
    # Hyprland: 各モニターのバーなどが占める幅(reserved)から、X11 の座標で作業領域を計算する
    [[ -f "$here/clistux-workarea-hyprland.py" ]] || exit 0
    new=$(timeout 5 hyprctl monitors -j 2>/dev/null | timeout 5 python3 -I "$here/clistux-workarea-hyprland.py" 2>/dev/null) || exit 0
elif [[ "${XDG_CURRENT_DESKTOP:-}" == *COSMIC* ]]; then
    # COSMIC: 透明な仮の窓を最大化させて、空いた範囲を測る
    probe="$here/clistux-workarea.py"
    [[ -f "$probe" ]] || exit 0
    new=$(timeout 10 python3 -I "$probe" 2>/dev/null) || exit 0
else
    exit 0
fi
# 「x, y, 幅, 高さ」の4つ組(負にはならない)
[[ "$new" =~ ^[0-9]+(,\ [0-9]+)*$ ]] || exit 0
(( $(tr -cd ',' <<< "$new" | wc -c) % 4 == 3 )) || exit 0
old=$(xprop -root _GTK_WORKAREAS_D0 2>/dev/null | sed -n 's/^[^=]*= //p')
[[ "$new" == "$old" ]] && exit 0

# ほかのプログラム(GTK に対応したウィンドウマネージャなど)が設定した値は上書きしない。
# 自分で設定した値は _CLISTUX_WORKAREA にも書いておき、それと同じときだけ書き換える
mine=$(xprop -root _CLISTUX_WORKAREA 2>/dev/null | sed -n 's/^[^=]*= //p')
[[ -n "$old" && "$old" != "$mine" ]] && exit 0

xprop -root -f _GTK_WORKAREAS_D0 32c -set _GTK_WORKAREAS_D0 "$new" || exit 0
xprop -root -f _CLISTUX_WORKAREA 32c -set _CLISTUX_WORKAREA "$new" 2>/dev/null || true

# Wine は画面の配置を覚えている。このプレフィックスで CSP・CLIP STUDIO が動いていなければ、
# wineserver を止めて新しい作業領域を読ませる(ほかのプレフィックスで動いている CSP は数えない)
prefix_busy() {
    local pid
    for pid in $(pgrep -u "$(id -u)" -f 'CLIPStudio[A-Za-z]*\.exe' 2>/dev/null); do
        tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$WINEPREFIX" && return 0
    done
    return 1
}
if [[ -n "${WINESERVER:-}" && -n "${WINEPREFIX:-}" ]] && ! prefix_busy; then
    "$WINESERVER" -k 2>/dev/null || true
    "$WINESERVER" -w 2>/dev/null || true
fi
exit 0
