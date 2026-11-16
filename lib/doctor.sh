# shellcheck shell=bash
# 状態の診断。よくある不具合の原因を調べて、わかる言葉で表示する。何も変えない。

doctor() {
    local problems=0

    if [[ -x "$WINE_DIR/bin/wine" ]]; then
        ok "Wine: $(readlink "$WINE_DIR")"
    else
        fail "Wine が入っていません。「$(basename "$0") install」を実行してください。"; problems=$((problems + 1))
    fi

    if [[ -f "$PREFIX/system.reg" ]]; then
        ok "プレフィックス: $PREFIX"
    else
        fail "プレフィックスがありません。「$(basename "$0") install」を実行してください。"; problems=$((problems + 1))
    fi

    if [[ -n "$(csp_exe paint)" ]]; then
        check_tested_version
    else
        fail "CSP が入っていません。「$(basename "$0") install」を実行してください。"; problems=$((problems + 1))
    fi

    [[ -x "$BIN_DIR/csp-launch" ]] && ok "起動スクリプト: $BIN_DIR/csp-launch" \
        || { fail "起動スクリプトがありません。「$(basename "$0") repair」を実行してください。"; problems=$((problems + 1)); }
    [[ -f "$APPS_DIR/clistux-paint.desktop" ]] && ok "アプリのメニューに登録されています" \
        || { warn "アプリのメニューに登録されていません。「$(basename "$0") repair」で登録します。"; }

    if font_present "${FONT_GOTHIC_CANDIDATES[0]}" || [[ -n "$(present_fonts "${FONT_GOTHIC_CANDIDATES[@]}")" ]]; then
        ok "日本語フォント: $(present_fonts "${FONT_GOTHIC_CANDIDATES[@]}" | cut -d';' -f1)"
    else
        fail "日本語フォントがありません: $(install_hint "$(distro_family)" font-jp)"; problems=$((problems + 1))
    fi

    webview2_status || problems=$((problems + 1))
    check_ntsync
    check_input_method

    # 取り残された Wine: CSP を閉じたのに Windows のプログラムが残っていると、次の起動が固まることがある
    if prefix_busy && ! pgrep -u "$(id -u)" -f 'CLIPStudio[A-Za-z]*\.exe' >/dev/null; then
        warn "CSP は動いていないのに、Windows のプログラムが残っています。"
        info "  CSP が起動しないときは「$(basename "$0") stop」で止めてください。"
    fi

    # TABMATE
    if tabmate_rule_installed; then
        ok "TABMATE の設定: 済み"
        local h found=0
        for h in /sys/class/hidraw/hidraw*; do
            [[ "$(readlink -f "$h/device" 2>/dev/null)" == *0005:0A5C:8502* ]] || continue
            found=1
            if [[ -r "/dev/$(basename "$h")" && -w "/dev/$(basename "$h")" ]]; then
                ok "TABMATE: 接続中で、使える状態です"
            else
                fail "TABMATE: 接続中ですが、読み書きできません。いったん切断して、つなぎ直してください。"; problems=$((problems + 1))
            fi
        done
        ((found)) || info "TABMATE: 今は接続されていません"
    else
        info "TABMATE の設定: まだ(使う場合は「$(basename "$0") tabmate」)"
    fi

    echo
    if ((problems)); then
        printf '%s%d 件の問題が見つかりました。%s\n' "$C_Y" "$problems" "$C_0"
    else
        printf '%s問題は見つかりませんでした。%s\n' "$C_G" "$C_0"
    fi
    info "起動の記録: $CLISTUX_STATE/launch.log"
}
