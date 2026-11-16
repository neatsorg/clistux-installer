# shellcheck shell=bash
# CSP 本体: インストーラを探して実行する。導入した CSP の場所と版を調べる。
# CSP は再配布せず、利用者が公式サイトからインストーラを入手する。

CSP_DOWNLOAD_PAGE="https://www.clipstudio.net/ja/dl/"

download_dirs() {
    local d
    d="$(xdg-user-dir DOWNLOAD 2>/dev/null)" && [[ -d "$d" ]] && echo "$d"
    for d in "$HOME/Downloads" "$HOME/ダウンロード"; do [[ -d "$d" ]] && echo "$d"; done
}

# 「ダウンロード」フォルダーにある、いちばん新しい版の CSP のインストーラ
find_csp_installer() {
    if [[ -n "${OPT_CSP_INSTALLER:-}" ]]; then
        [[ -f "$OPT_CSP_INSTALLER" ]] || die "指定された CSP のインストーラがありません: $OPT_CSP_INSTALLER"
        echo "$OPT_CSP_INSTALLER"; return
    fi
    local d
    while read -r d; do
        find "$d" -maxdepth 1 -type f -iname 'CSP_*w_setup*.exe' 2>/dev/null
    done < <(download_dirs | sort -u) | awk -F/ '{print $NF "\t" $0}' | sort -V | tail -1 | cut -f2
}

ask_for_csp_installer() {
    info "CLIP STUDIO PAINT のインストーラ(Windows 版)が「ダウンロード」フォルダーに見つかりません。"
    info "次の手順で入手してください:"
    info "  1. ブラウザで $CSP_DOWNLOAD_PAGE を開く"
    info "  2. 「Windows」版をダウンロードする(ファイル名は CSP_xxxw_setup.exe のような形です)"
    info "  3. ダウンロードが終わったら、もう一度このインストーラを実行する"
    info "別の場所に置いた場合は、--csp-installer でファイルを指定できます。"
    if command -v xdg-open >/dev/null && confirm "今ブラウザで開きますか? "; then
        (xdg-open "$CSP_DOWNLOAD_PAGE" >/dev/null 2>&1 &)
    fi
    die "CSP のインストーラが必要です。"
}

run_csp_installer() {
    local installer="$1"
    [[ -n "$installer" ]] || ask_for_csp_installer
    ok "CSP のインストーラ: $(basename "$installer")"
    info "CSP のインストーラの画面が開きます。画面の指示に従って進めてください。"
    printf '  %s！！以下に注意してください。！！%s\n' "$C_Y$C_B" "$C_0"
    info "  ・インストール先は変えずに、そのまま進めてください。"
    info "  ・最後の画面で「CLIP STUDIO を起動する」などにチェックがあれば、外してから「完了」を押してください。"
    info "  ・インストーラの画面が閉じるまで、この端末はそのままにしておいてください。インストール終了を検知すると、自動的に次の処理が開始されます。"
    run_logged wine "$installer"
    # インストーラが終わっても、インストーラが入れた常駐のプログラム(WebView2 の自動更新など)が残ることがある。
    # インストールは済んでいるので止める(待ち続けないように)。
    wineserver -k 2>/dev/null || true
    wineserver -w
    [[ -n "$(csp_exe paint)" ]] || die "CSP が入っていないようです。" "インストーラの画面を最後まで進めたか確かめて、もう一度実行してください。"
    ok "CSP を入れました($(csp_version))"
}

# 導入した exe の場所(版を含むパスを決め打ちにしない)
#   csp_exe paint  → CLIPStudioPaint.exe
#   csp_exe studio → CLIPStudio.exe
csp_exe() {
    local name
    case "$1" in
        paint) name=CLIPStudioPaint.exe ;;
        studio) name=CLIPStudio.exe ;;
        *) return 1 ;;
    esac
    find "$PREFIX/drive_c/Program Files/CELSYS" -maxdepth 4 -type f -name "$name" 2>/dev/null | sort -V | tail -1
}

# CSP の版(exe の版情報から読む)
csp_version() {
    local exe
    exe="$(csp_exe paint)"
    [[ -n "$exe" ]] || return 1
    python3 -I - "$exe" <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read()
i = d.find(struct.pack('<I', 0xFEEF04BD))
if i < 0:
    sys.exit(1)
ms, ls = struct.unpack_from('<II', d, i + 8)
print(f'{ms >> 16}.{ms & 0xffff}.{ls >> 16}.{ls & 0xffff}')
EOF
}

# 動作を確かめた版か(spec 設計の三本柱 1。未確認でも止めない)
check_tested_version() {
    local v
    v="$(csp_version)" || return 0
    if grep -qxF "$v" "$CLISTUX_ROOT/data/tested-versions"; then
        ok "CSP $v は動作を確かめた版です"
    else
        warn "CSP $v は、まだこのインストーラで動作を確かめていない版です。"
        info "  多くの場合はそのまま動きます。うまく動かないときは、プロジェクトに知らせてください。"
    fi
}
