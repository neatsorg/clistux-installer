# shellcheck shell=bash
# プレフィックスの作成と、CSP 用の設定。

# 日本語フォントの候補(優先する順)。日本語の字形の書体名で決め打ちにする(spec 4.7)。
FONT_GOTHIC_CANDIDATES=("Noto Sans CJK JP" "Source Han Sans JP" "IPAexGothic" "BIZ UDPGothic" "VL Gothic")
FONT_MINCHO_CANDIDATES=("Noto Serif CJK JP" "Source Han Serif JP" "IPAexMincho" "BIZ UDPMincho")

# このツールが前回入れた設定の値の記録(更新のときに、利用者が変えた値を見分けるため)
SETTINGS_RECORD="$CLISTUX_DATA/settings-applied.json"

font_present() { [[ -n "$(fc-list ":family=$1" family 2>/dev/null | head -1)" ]]; }

# 候補のうち、この PC にあるものを ; でつないで返す
present_fonts() {
    local f out=()
    for f in "$@"; do font_present "$f" && out+=("$f"); done
    local IFS=';'; echo "${out[*]}"
}

create_prefix() {
    if [[ -f "$PREFIX/system.reg" ]]; then
        info "Wine を更新した場合に備えて、プレフィックスを最新にしています…"
        run_logged wine wineboot -u || die "プレフィックスの更新に失敗しました。"
        wineserver -w
        ok "プレフィックス: $PREFIX(既存)"
        return
    fi
    info "CSP 専用の Windows 環境(プレフィックス)を作っています。1分ほどかかります…"
    mkdir -p "$PREFIX"
    run_logged wine wineboot -i || die "プレフィックスの作成に失敗しました。"
    wineserver -w
    [[ -f "$PREFIX/system.reg" ]] || die "プレフィックスの作成に失敗しました。"
    ok "プレフィックス: $PREFIX"
}

# 何度実行しても同じ結果になる。CSP の導入・更新のたびに実行する。
# 設定を入れる。mode は full(すべて入れる。導入・修復)か preserve(利用者が変えた値は残す。更新)。
apply_settings() {
    local mode="${1:-full}" gothic mincho reg kept
    gothic="$(present_fonts "${FONT_GOTHIC_CANDIDATES[@]}")"
    mincho="$(present_fonts "${FONT_MINCHO_CANDIDATES[@]}")"
    if [[ -z "$gothic" ]]; then
        warn "日本語のフォントが見つかりません。CSP の画面の文字が □ になることがあります。"
        info "  入れるには: $(install_hint "$(distro_family)" font-jp)"
        info "  入れた後に「$(basename "$0") repair」を実行すると、設定を入れ直します。"
    else
        ok "日本語フォント: ${gothic%%;*}${mincho:+、${mincho%%;*}}"
    fi

    # 登録されているサービスだけを止める
    local svc disable=()
    for svc in edgeupdate edgeupdatem; do
        grep -qF "[System\\\\ControlSet001\\\\Services\\\\$svc]" "$PREFIX/system.reg" && disable+=("$svc")
    done

    # レジストリのファイルに、最新の値が書き出されているようにする(今の値を読むため)
    wineserver -w
    reg="$CLISTUX_STATE/csp-settings.reg"
    kept="$(python3 -I "$CLISTUX_ROOT/lib/make-settings-reg.py" --out "$reg" --prefix "$PREFIX" \
        --applied "$SETTINGS_RECORD" --mode "$mode" --gothic "$gothic" --mincho "$mincho" \
        --disable "$(IFS=';'; echo "${disable[*]}")")" || die "設定ファイルを作れませんでした。"
    run_logged wine regedit /S "Z:${reg//\//\\}" || die "設定を入れられませんでした。"
    mv "$SETTINGS_RECORD.new" "$SETTINGS_RECORD"
    if [[ -n "$kept" ]]; then
        info "次の設定は、変えられていたので、そのままにしました(元に戻すには「$(basename "$0") repair」):"
        while IFS=$'\t' read -r _ key name; do info "  $key の $name"; done <<< "$kept"
    fi
    # 設定を入れる前に起動したサービスが残っていることがあるので、止めて読み直させる
    wineserver -k 2>/dev/null || true
    wineserver -w
    ok "CSP 用の設定を入れました"
}
