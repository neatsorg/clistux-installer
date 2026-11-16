# shellcheck shell=bash
# WebView2(CSP・CLIP STUDIO の中の Web の画面に使う部品)。
#
# CSP のインストーラが入れる WebView2(5.1.5 では 115)は、Wine ではブラウザが起動中に止まって表示できない。
# そこで、Microsoft が配っている版固定の WebView2(Fixed Version)の最新版を入れ、動くことを確かめてから使う。
#   - 入手: Microsoft の WebView2 のダウンロードページに載っている、最新の x64 の CAB(Microsoft のサーバー)
#   - 確認: wv2check.exe でページを1枚表示できるか
#   - 使わせ方: レジストリのポリシー BrowserExecutableFolder(exe の名前ごと)
#   - 控え: 前に使っていた版を1つ残し、「clistux webview2 --previous」で戻せる
# Microsoft は最新とその前の数版しか配っていないので、版を決め打ちにしない。

WV2_PAGE="https://developer.microsoft.com/en-us/microsoft-edge/webview2/"
WV2_ROOT_WIN='C:\Program Files\clistux\WebView2'
WV2_STATE="$CLISTUX_DATA/webview2.state"
WV2_APPS=(CLIPStudioPaint.exe CLIPStudio.exe)

wv2_root() { win_to_unix "$WV2_ROOT_WIN"; }
wv2_state_get() { [[ -f "$WV2_STATE" ]] && sed -n "s/^$1=//p" "$WV2_STATE" || true; }
wv2_state_set() {
    local current="$1" previous="$2"
    printf 'current=%s\nprevious=%s\n' "$current" "$previous" > "$WV2_STATE"
}

# wv2check.exe の置き場所: Wine の配布物に入っているもの、なければ手元でビルドしたもの
wv2check_source() {
    local d
    for d in "$WINE_DIR/share/clistux/wv2check" "$CLISTUX_CACHE/wv2check"; do
        [[ -f "$d/wv2check.exe" && -f "$d/WebView2Loader.dll" ]] && { echo "$d"; return; }
    done
    return 1
}

# Microsoft のダウンロードページから、最新の x64 の固定版の「版 URL」を返す
wv2_latest() {
    local page="$CLISTUX_CACHE/webview2/page.html"
    mkdir -p "$CLISTUX_CACHE/webview2"
    curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 -A 'Mozilla/5.0' -o "$page" "$WV2_PAGE" || return 1
    python3 -I - "$page" <<'EOF'
import re, sys
s = open(sys.argv[1], encoding='utf-8', errors='replace').read().replace('\\u002F', '/')
urls = set(re.findall(r'https://msedge\.sf\.dl\.delivery\.mp\.microsoft\.com/filestreamingservice/files/'
                      r'[0-9a-f-]+/Microsoft\.WebView2\.FixedVersionRuntime\.([0-9.]+)\.x64\.cab', s))
full = {v: re.search(r'https://msedge\.sf\.dl\.delivery\.mp\.microsoft\.com/filestreamingservice/files/'
                     r'[0-9a-f-]+/Microsoft\.WebView2\.FixedVersionRuntime\.' + re.escape(v) + r'\.x64\.cab', s).group(0)
        for v in urls}
if not full:
    sys.exit(1)
v = max(full, key=lambda x: tuple(int(n) for n in x.split('.')))
print(v, full[v])
EOF
}

# 版を確かめる。0 なら使える。
wv2_check_version() {
    local ver="$1" src
    src="$(wv2check_source)" || { warn "WebView2 を確かめる道具(wv2check)が見つかりません"; return 1; }
    mkdir -p "$(win_to_unix 'C:\Program Files\clistux\wv2check')"
    install -m 644 "$src/wv2check.exe" "$src/WebView2Loader.dll" "$(win_to_unix 'C:\Program Files\clistux\wv2check')/"
    log "wv2check $ver"
    ( wine_env; timeout 180 "$WINE_DIR/bin/wine" 'C:\Program Files\clistux\wv2check\wv2check.exe' "$WV2_ROOT_WIN\\$ver" 90 ) >> "$LOG" 2>&1
}

# レジストリのポリシーで、CSP と CLIP STUDIO に使わせる版を決める
wv2_apply_policy() {
    local ver="$1" reg="$CLISTUX_STATE/webview2-policy.reg" app
    {
        printf 'Windows Registry Editor Version 5.00\r\n\r\n'
        printf '[HKEY_LOCAL_MACHINE\\Software\\Policies\\Microsoft\\Edge\\WebView2\\BrowserExecutableFolder]\r\n'
        for app in "${WV2_APPS[@]}"; do
            printf '"%s"="%s"\r\n' "$app" "${WV2_ROOT_WIN//\\/\\\\}\\\\$ver"
        done
    } | iconv -f UTF-8 -t UTF-16 > "$reg"
    run_logged wine regedit /S "Z:${reg//\//\\}" || return 1
    wineserver -w
}

# 最新版を入れて確かめ、使えれば切り替える。何度実行しても同じ結果になる。
update_webview2() {
    local latest ver url cab root current previous
    root="$(wv2_root)"
    current="$(wv2_state_get current)"
    previous="$(wv2_state_get previous)"

    info "WebView2 の最新版を調べています…"
    if ! latest="$(wv2_latest)"; then
        if [[ -n "$current" ]]; then
            warn "WebView2 の最新版を調べられませんでした。今の版($current)を使い続けます。"
            return 0
        fi
        warn "WebView2 を入手できませんでした。CSP の中の Web の画面(お知らせ・素材など)が白くなります。"
        info "  インターネットにつながっているか確かめて、あとで「$(basename "$0") webview2」を実行してください。"
        return 0
    fi
    ver="${latest%% *}"; url="${latest#* }"

    if [[ "$ver" == "$current" && -f "$root/$ver/msedgewebview2.exe" ]]; then
        wv2_apply_policy "$ver"
        ok "WebView2: $ver(最新)"
        return 0
    fi

    cab="$CLISTUX_CACHE/webview2/Microsoft.WebView2.FixedVersionRuntime.$ver.x64.cab"
    if [[ ! -f "$cab" ]]; then
        info "WebView2 $ver をダウンロードしています(約 300 MB)…"
        # URL は wv2_latest が Microsoft のサーバー(https)のものに限っている。転送先も https に限る。
        run_logged curl -fL --proto '=https' --proto-redir '=https' --max-redirs 3 --retry 3 -o "$cab.part" "$url" \
            || { rm -f "$cab.part"; warn "WebView2 のダウンロードに失敗しました。"; return 0; }
        mv "$cab.part" "$cab"
    fi
    info "WebView2 $ver を展開しています…"
    rm -rf "$root/$ver" "$root/.extract"
    mkdir -p "$root/.extract"
    if ! run_logged cabextract -q -d "$root/.extract" "$cab"; then
        # 壊れたファイルは消して、次回に取り直す
        rm -rf "$root/.extract" "$cab"
        warn "WebView2 の展開に失敗しました。もう一度「$(basename "$0") webview2」を実行してください。"
        return 0
    fi
    mv "$root/.extract/Microsoft.WebView2.FixedVersionRuntime.$ver.x64" "$root/$ver" && rm -rf "$root/.extract"

    info "WebView2 $ver が動くかを確かめています…"
    if wv2_check_version "$ver"; then
        wv2_apply_policy "$ver" || die "WebView2 の設定を入れられませんでした。"
        if [[ -n "$current" && "$current" != "$ver" ]]; then
            wv2_state_set "$ver" "$current"
            ok "WebView2: $ver に更新しました(前の $current は控えとして残しました)"
        else
            wv2_state_set "$ver" "$previous"
            ok "WebView2: $ver"
        fi
        wv2_prune "$(wv2_state_get current)" "$(wv2_state_get previous)"
        rm -f "$cab"
    else
        rm -rf "${root:?}/$ver"
        if [[ -n "$current" ]]; then
            warn "WebView2 の最新版($ver)は、この環境ではうまく動きませんでした。今の版($current)を使い続けます。"
        else
            warn "WebView2 $ver がうまく動きませんでした。CSP の中の Web の画面(お知らせ・素材など)が白くなることがあります。"
        fi
    fi
}

# 使う版と控えの版のほかは片付ける
wv2_prune() {
    local keep1="$1" keep2="$2" d name
    for d in "$(wv2_root)"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        [[ "$name" == "$keep1" || "$name" == "$keep2" ]] && continue
        rm -rf "${d:?}"
    done
}

# 控えの版に戻す
webview2_previous() {
    local current previous root
    root="$(wv2_root)"
    current="$(wv2_state_get current)"
    previous="$(wv2_state_get previous)"
    [[ -n "$previous" && -f "$root/$previous/msedgewebview2.exe" ]] || die "戻せる WebView2 の版がありません。"
    wv2_apply_policy "$previous" || die "WebView2 の設定を入れられませんでした。"
    wv2_state_set "$previous" "$current"
    ok "WebView2 を $previous に戻しました(元の $current は控えにしました)"
}

webview2_status() {
    local current previous
    current="$(wv2_state_get current)"
    previous="$(wv2_state_get previous)"
    if [[ -n "$current" && -f "$(wv2_root)/$current/msedgewebview2.exe" ]]; then
        ok "WebView2: $current${previous:+(控え: $previous)}"
    else
        warn "WebView2 が準備されていません。CSP の中の Web の画面が白くなります。「$(basename "$0") webview2」で準備します。"
        return 1
    fi
}
