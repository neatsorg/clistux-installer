#!/usr/bin/env bash
# clistux: CLIP STUDIO PAINT / CLIP STUDIO を起動する。
#   csp-launch paint [ファイル]   CLIP STUDIO PAINT(.clip などを開く)
#   csp-launch studio             CLIP STUDIO
# このスクリプトは <データの置き場所>/bin/ に置かれる。Wine とプレフィックスは、その一つ上にある。
# CSP の場所は毎回探すので、CSP を更新してフォルダーの名前が変わっても動く。
set -u

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DATA="$(dirname "$HERE")"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/clistux"
mkdir -p "$STATE"

export WINEPREFIX="$DATA/prefix"
export WINESERVER="$DATA/wine/bin/wineserver"
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d"
export WINEDEBUG="${WINEDEBUG:--all}"

notify_error() {
    command -v notify-send >/dev/null && notify-send -a "$title" "起動できませんでした" "$1" 2>/dev/null
    echo "csp-launch: $1" >&2
    exit 1
}

title="CLIP STUDIO PAINT"
case "${1:-paint}" in
    paint) name=CLIPStudioPaint.exe; title="CLIP STUDIO PAINT" ;;
    studio) name=CLIPStudio.exe; title="CLIP STUDIO" ;;
    *) notify_error "使い方: csp-launch paint [ファイル] | studio" ;;
esac
shift || true

exe="$(find "$WINEPREFIX/drive_c/Program Files/CELSYS" -maxdepth 4 -type f -name "$name" 2>/dev/null | sort -V | tail -1)"
[[ -n "$exe" ]] || notify_error "$name が見つかりません。端末で「clistux doctor」を実行してください。"

# 日本語入力: Wine は XIM で入力メソッドにつながる。デスクトップによっては(COSMIC など)
# XMODIFIERS がアプリに渡らないので、動いている入力メソッドに合わせてここで補う。
if [[ -z "${XMODIFIERS:-}" ]]; then
    if pgrep -u "$(id -u)" -x fcitx5 >/dev/null 2>&1; then
        export XMODIFIERS=@im=fcitx
    elif pgrep -u "$(id -u)" -f ibus-daemon >/dev/null 2>&1; then
        export XMODIFIERS=@im=ibus
    fi
fi

# COSMIC: 作業領域(パネルを除いた範囲)を X11 に知らせる。最大化した CSP がパネルに重ならないように。
"$HERE/clistux-workarea.sh" || true

args=()
if [[ $# -gt 0 && -e "$1" ]]; then
    args+=("$("$DATA/wine/bin/winepath" -w "$1" 2>/dev/null)")
fi

# ---- 起動して見守る -------------------------------------------------------------
# 落ちたとき、いつまでも画面が出ないときは、デスクトップの通知で次にすることを知らせる(PC に不慣れな人向け)。
log="$STATE/launch.log"
offset=$(stat -c %s "$log" 2>/dev/null || echo 0)
"$DATA/wine/bin/wine" "$exe" "${args[@]}" >> "$log" 2>&1 &
pid=$!

notify() {
    command -v notify-send >/dev/null || return 0
    notify-send -a "$title" -i dialog-warning "$1" "$2" 2>/dev/null || true
}
crashed() { tail -c +"$((offset + 1))" "$log" 2>/dev/null | grep -q 'Unhandled \(page fault\|exception\)'; }
window_shown() {
    command -v xprop >/dev/null || return 0     # 調べられないときは見守らない
    local x p
    for x in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+'); do
        xprop -id "$x" WM_CLASS 2>/dev/null | grep -qi "\"${name,,}\"" || continue
        # 別の環境(別のプレフィックス)の CSP のウィンドウは数えない
        p=$(xprop -id "$x" _NET_WM_PID 2>/dev/null | awk '{print $3}')
        [[ -n "$p" ]] && tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$WINEPREFIX" && return 0
    done
    return 1
}

for _ in $(seq 120); do
    sleep 1
    if crashed; then
        notify "$title が起動中に終了しました" \
            "端末で「clistux doctor」を実行すると、原因を調べられます。起動の記録: $log"
        exit 1
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        # すでに開いている CSP にファイルを渡して終わった場合などは、正常
        wait "$pid" && exit 0
        notify "$title を起動できませんでした" \
            "端末で「clistux doctor」を実行すると、原因を調べられます。起動の記録: $log"
        exit 1
    fi
    window_shown && exit 0
done
notify "$title の画面が出ません" \
    "しばらく待っても出ないときは、端末で「clistux stop」を実行してから、もう一度起動してください。"
exit 0
