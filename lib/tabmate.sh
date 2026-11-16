# shellcheck shell=bash
# CLIP STUDIO TABMATE(spec 8)。Wine 側の設定は apply_settings が入れる。ここでは root が必要な udev ルールを置く。

TABMATE_RULE=/etc/udev/rules.d/71-clistux-tabmate.rules

tabmate_rule_installed() { cmp -s "$CLISTUX_ROOT/integration/udev/71-clistux-tabmate.rules" "$TABMATE_RULE"; }

setup_tabmate() {
    if tabmate_rule_installed; then
        ok "TABMATE の設定は済んでいます"
    else
        info "CLIP STUDIO TABMATE を CSP で使うには、TABMATE 専用の設定(udev ルール)を次の場所に置きます。"
        info "この設定を保存する際には管理者のパスワードを聞かれますので入力してください:"
        info "    $TABMATE_RULE"
        info "  この設定の対象は TABMATE(Bluetooth接続)のみで、ほかの機器に影響するものではありません。"
        confirm "設定しますか?" || { warn "TABMATE の設定をとばしました(あとで「$(basename "$0") tabmate」で設定できます)"; return 0; }
        sudo install -m 644 "$CLISTUX_ROOT/integration/udev/71-clistux-tabmate.rules" "$TABMATE_RULE" \
            || die "TABMATE の設定を置けませんでした。"
        sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=hidraw
        ok "TABMATE の設定を置きました"
    fi
    info "TABMATE の使い方:"
    info "  ・はじめての接続(ペアリング)は、デスクトップの Bluetooth の設定から行ってください。"
    info "  ・TABMATE は10分操作しないと眠ります。CLIP STUDIO ボタン以外のボタンを押すと、また接続します。"
    info "  ・CSP の「ファイル」メニュー →「CLIP STUDIO TABMATE」で、ボタンの割り当てを変えられます。"
}

remove_tabmate() {
    [[ -f "$TABMATE_RULE" ]] || return 0
    info "TABMATE の設定($TABMATE_RULE)を消すには、管理者のパスワードが要ります。"
    confirm "消しますか?" || return 0
    sudo rm -f "$TABMATE_RULE" && sudo udevadm control --reload && ok "TABMATE の設定を消しました"
}
