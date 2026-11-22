# shellcheck shell=bash
# デスクトップとの統合: 起動スクリプト、アプリのメニュー、.clip ファイルの関連付け、アイコン。

CLIP_MIME="application/x-clip-studio-paint"

install_launcher() {
    mkdir -p "$BIN_DIR"
    install -m 755 "$CLISTUX_ROOT/integration/launch.sh" "$BIN_DIR/csp-launch"
    install -m 755 "$CLISTUX_ROOT/integration/workarea/clistux-workarea.sh" "$BIN_DIR/clistux-workarea.sh"
    install -m 644 "$CLISTUX_ROOT/integration/workarea/clistux-workarea.py" "$BIN_DIR/clistux-workarea.py"
    install -m 644 "$CLISTUX_ROOT/integration/workarea/clistux-workarea-hyprland.py" "$BIN_DIR/clistux-workarea-hyprland.py"
    ok "起動スクリプト: $BIN_DIR/csp-launch"
}

write_desktop_entry() {
    local id="$1" name="$2" comment="$3" kind="$4" icon="$5" extra="$6"
    cat > "$APPS_DIR/$id.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Comment=$comment
Exec="$BIN_DIR/csp-launch" $kind${extra:+ $extra}
Icon=$icon
Terminal=false
Categories=Graphics;2DGraphics;RasterGraphics;
StartupWMClass=$([[ $kind == paint ]] && echo clipstudiopaint.exe || echo clipstudio.exe)
X-CSP-Linux=1
EOF
}

install_desktop() {
    mkdir -p "$APPS_DIR" "$ICON_DIR" "$MIME_DIR/packages"
    local paint studio icon_paint=applications-graphics icon_studio=applications-graphics
    paint="$(csp_exe paint)"
    studio="$(csp_exe studio)"
    if [[ -n "$paint" ]] && python3 -I "$CLISTUX_ROOT/lib/extract-icon.py" "$paint" "$ICON_DIR/clistux-paint.png"; then
        icon_paint=clistux-paint
    fi
    if [[ -n "$studio" ]] && python3 -I "$CLISTUX_ROOT/lib/extract-icon.py" "$studio" "$ICON_DIR/clistux-studio.png"; then
        icon_studio=clistux-studio
    fi

    write_desktop_entry clistux-paint "CLIP STUDIO PAINT" "イラスト・マンガ・アニメーション制作ソフト" paint "$icon_paint" "%f"
    echo "MimeType=$CLIP_MIME;" >> "$APPS_DIR/clistux-paint.desktop"
    write_desktop_entry clistux-studio "CLIP STUDIO" "素材の管理・ダウンロード、アカウント" studio "$icon_studio" ""

    # .clip ファイルを CLIP STUDIO PAINT で開けるようにする
    cat > "$MIME_DIR/packages/clistux.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="$CLIP_MIME">
    <comment>CLIP STUDIO PAINT ファイル</comment>
    <glob pattern="*.clip"/>
  </mime-type>
</mime-info>
EOF
    command -v update-mime-database >/dev/null && run_logged update-mime-database "$MIME_DIR"
    command -v update-desktop-database >/dev/null && run_logged update-desktop-database "$APPS_DIR"
    command -v xdg-mime >/dev/null && run_logged xdg-mime default clistux-paint.desktop "$CLIP_MIME"
    command -v gtk-update-icon-cache >/dev/null && run_logged gtk-update-icon-cache -q -t "${ICON_DIR%/256x256/apps}"
    ok "アプリのメニューに「CLIP STUDIO PAINT」と「CLIP STUDIO」を登録しました"
}

remove_desktop() {
    rm -f "$APPS_DIR/clistux-paint.desktop" "$APPS_DIR/clistux-studio.desktop" \
          "$ICON_DIR/clistux-paint.png" "$ICON_DIR/clistux-studio.png" "$MIME_DIR/packages/clistux.xml"
    command -v update-mime-database >/dev/null && run_logged update-mime-database "$MIME_DIR"
    command -v update-desktop-database >/dev/null && run_logged update-desktop-database "$APPS_DIR"
    ok "アプリのメニュー登録を消しました"
}

# 日本語入力: 起動スクリプトが XMODIFIERS を補うので、利用者の設定ファイルは変えない。ここでは状態を知らせるだけ。
check_input_method() {
    if pgrep -u "$(id -u)" -x fcitx5 >/dev/null 2>&1; then
        ok "日本語入力: fcitx5(CSP の起動時に自動で連携します)"
    elif pgrep -u "$(id -u)" -f ibus-daemon >/dev/null 2>&1; then
        ok "日本語入力: IBus(CSP の起動時に自動で連携します)"
    else
        warn "日本語入力(fcitx5 / IBus)が動いていません。CSP で日本語を入力するには、どちらかが必要です。"
    fi
}

# このツール自身を <データの置き場所>/tool に写し、~/.local/bin/clistux から呼べるようにする。
# 利用者がダウンロードしたフォルダを消しても、あとで更新・診断・削除ができるように。
SELF_DIR="$CLISTUX_DATA/tool"
SELF_LINK="$HOME/.local/bin/clistux"

install_self() {
    local src="$CLISTUX_ROOT"     # 一時的な場所から動いているときも、実行中のスクリプトの場所から写す
    if [[ "$src" != "$SELF_DIR" ]]; then
        rm -rf "$SELF_DIR.new"
        mkdir -p "$SELF_DIR.new"
        cp -r "$src/clistux" "$src/lib" "$src/integration" "$src/data" "$SELF_DIR.new/"
        [[ -f "$src/install.sh" ]] && cp "$src/install.sh" "$SELF_DIR.new/"
        rm -rf "$SELF_DIR.new/integration/wv2check"     # 道具は Wine の配布物に入っている
        rm -rf "$SELF_DIR" && mv "$SELF_DIR.new" "$SELF_DIR"
    fi
    mkdir -p "$(dirname "$SELF_LINK")"
    ln -sfn "$SELF_DIR/clistux" "$SELF_LINK"
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        ok "このツールは、端末で「clistux」と入力すれば、いつでも呼び出せます"
    else
        ok "このツールは、端末で「$SELF_LINK」と入力すれば、いつでも呼び出せます"
    fi
}

remove_self() {
    [[ "$(readlink "$SELF_LINK" 2>/dev/null)" == "$SELF_DIR/clistux" ]] && rm -f "$SELF_LINK"
    rm -rf "$SELF_DIR"
}
