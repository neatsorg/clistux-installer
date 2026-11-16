# shellcheck shell=bash
# 共通: 置き場所、画面への表示、ログ、確認、Wine の呼び出し。
# 画面には、PC に不慣れな人にもわかる言葉で出す。詳しい出力はログに残す。

# ---- 置き場所(環境変数で変えられる) -------------------------------------------
CLISTUX_DATA="${CLISTUX_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/clistux}"   # Wine・プレフィックス・起動スクリプト
CLISTUX_CACHE="${CLISTUX_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/clistux}"     # ダウンロードしたもの
CLISTUX_STATE="${CLISTUX_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/clistux}" # ログ
WINE_DIR="$CLISTUX_DATA/wine"          # 使う Wine(版つきのフォルダへのリンク)
PREFIX="$CLISTUX_DATA/prefix"          # CSP 専用の Wine のプレフィックス
BIN_DIR="$CLISTUX_DATA/bin"            # 起動スクリプトなど
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
MIME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mime"

mkdir -p "$CLISTUX_STATE"
LOG="${LOG:-$CLISTUX_STATE/$(date +%Y%m%d-%H%M%S)-${CLISTUX_COMMAND:-run}.log}"

# ---- 表示 -----------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_B=$'\e[1m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_0=$'\e[0m'
else
    C_B=; C_G=; C_Y=; C_R=; C_0=
fi

STEP=0
STEPS=0
log()   { printf '%s %s\n' "$(date +%T)" "$*" >> "$LOG"; }
step()  { STEP=$((STEP + 1)); printf '\n%s[%d/%d] %s%s\n' "$C_B" "$STEP" "$STEPS" "$*" "$C_0"; log "== [$STEP/$STEPS] $*"; }
info()  { printf '  %s\n' "$*"; log "$*"; }
ok()    { printf '  %s✔%s %s\n' "$C_G" "$C_0" "$*"; log "OK: $*"; }
warn()  { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*"; log "WARN: $*"; }
fail()  { printf '  %s✘%s %s\n' "$C_R" "$C_0" "$*"; log "NG: $*"; }

# 続けられないときに呼ぶ。原因と、次にすることを表示して終わる。
die() {
    printf '\n%sうまくいきませんでした:%s %s\n' "$C_R" "$C_0" "$1" >&2
    [[ -n "${2:-}" ]] && printf '  %s\n' "$2" >&2
    printf '  詳しい記録: %s\n' "$LOG" >&2
    printf '  状態の診断: %s doctor\n' "$(basename "$0")" >&2
    log "DIE: $*"
    exit 1
}

# はい/いいえ を聞く。既定は「いいえ」。対話できないときは「いいえ」。
confirm() {
    local answer
    [[ -t 0 ]] || return 1
    read -r -p "  $*（Y または N を入力して、Enter キーを押してください。それ以外は N と同じです） [y/N] " answer
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] || "$answer" == はい ]]
}

# 時間のかかるコマンドを、出力をログに回して実行する
run_logged() {
    log "\$ $*"
    "$@" >> "$LOG" 2>&1
}

# ---- Wine -----------------------------------------------------------------------
wine_env() {
    export WINEPREFIX="$PREFIX"
    export WINESERVER="$WINE_DIR/bin/wineserver"
    export WINEARCH=win64
    # winemenubuilder: Wine に勝手にメニューの項目を作らせない(起動スクリプト経由の項目を自分で作る)
    # mscoree・mshtml: Wine Mono・Gecko の導入を聞かれないようにする(CSP には要らない。spec 4.6)
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d"
    export WINEDEBUG="${WINEDEBUG:--all}"
}
wine()       { wine_env; "$WINE_DIR/bin/wine" "$@"; }
wineserver() { wine_env; "$WINE_DIR/bin/wineserver" "$@"; }

# このプレフィックスで、利用者のプログラム(CSP、CLIP STUDIO、インストーラなど)が動いているか。
# Wine 自身のサービス(C:\windows\ の下)と WebView2 の自動更新は数えない。
prefix_busy() {
    local pid cmd
    for pid in $(pgrep -u "$(id -u)" -f '\.exe' 2>/dev/null); do
        [[ "$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^WINEPREFIX=//p')" == "$PREFIX" ]] || continue
        cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
        [[ "${cmd,,}" == c:\\windows\\* || "$cmd" == *MicrosoftEdgeUpdate.exe* ]] && continue
        return 0
    done
    return 1
}

# Windows のパス(C:\...)を、このプレフィックスの中の Linux のパスにする
win_to_unix() {
    local p="${1#[Cc]:}"
    printf '%s/drive_c%s\n' "$PREFIX" "${p//\\//}"
}
