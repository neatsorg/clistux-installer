# shellcheck shell=bash
# Wine の入手と配置。
# 配る Wine は wine/build.sh で作ったもの(公式のソース + このプロジェクトのパッチ)。
# 入手先: --wine-archive で渡したファイル、なければ $CLISTUX_CACHE/dist の最新、なければ公開先からダウンロード(未公開)。

WINE_RELEASE_URL="${WINE_RELEASE_URL:-}"   # 公開したら、GitHub Releases の URL をここに書く

# 手元にある、チェックサムのそろった最新の配布ファイル(無ければ空)。見つからなくても失敗にはしない。
find_wine_archive() {
    if [[ -n "${OPT_WINE_ARCHIVE:-}" ]]; then
        echo "$OPT_WINE_ARCHIVE"; return 0
    fi
    local f found=()
    for f in "$CLISTUX_CACHE"/dist/wine-*-csp*-x86_64.tar.xz; do
        [[ -f "$f" && -f "$f.sha256" ]] && found+=("$f")
    done
    ((${#found[@]})) && printf '%s\n' "${found[@]}" | sort -V | tail -1
    return 0
}

# Wine を配置する。同じものが既にあれば何もしない(何度実行しても同じ)。
install_wine() {
    local archive name sum
    archive="$(find_wine_archive)"
    if [[ -z "$archive" ]]; then
        [[ -n "$WINE_RELEASE_URL" ]] || die "Wine の配布ファイルが見つかりません。" \
            "今は公開前のため、wine/build.sh で作ったファイルを --wine-archive で指定してください。"
        mkdir -p "$CLISTUX_CACHE/dist"
        archive="$CLISTUX_CACHE/dist/$(basename "$WINE_RELEASE_URL")"
        info "Wine をダウンロードしています…"
        # 一時的な名前で受け取り、チェックサムを確かめてから正式な名前にする(途中で失敗したものを次回に使わない)
        rm -f "$archive.part" "$archive.sha256.part"
        run_logged curl -fL --proto '=https' --proto-redir '=https' --retry 3 -o "$archive.sha256.part" "$WINE_RELEASE_URL.sha256" \
            || die "Wine のチェックサムのダウンロードに失敗しました。" "インターネットにつながっているか確かめてください。"
        run_logged curl -fL --proto '=https' --proto-redir '=https' --retry 3 -o "$archive.part" "$WINE_RELEASE_URL" \
            || die "Wine のダウンロードに失敗しました。" "インターネットにつながっているか確かめてください。"
        sum="$(awk '{print $1}' "$archive.sha256.part")"
        if ! echo "$sum  $archive.part" | sha256sum -c --status -; then
            rm -f "$archive.part" "$archive.sha256.part"
            die "ダウンロードした Wine が壊れています。" "もう一度実行してください。"
        fi
        mv "$archive.sha256.part" "$archive.sha256"
        mv "$archive.part" "$archive"
    fi
    [[ -f "$archive" ]] || die "Wine の配布ファイルがありません: $archive"

    # チェックサムで、壊れていない(書き換えられていない)ことを確かめる
    if [[ -f "$archive.sha256" ]]; then
        sum="$(awk '{print $1}' "$archive.sha256")"
        echo "$sum  $archive" | sha256sum -c --status - || die "Wine の配布ファイルが壊れています: $archive" "ファイルを消して、もう一度実行してください。"
        ok "Wine の配布ファイルを確かめました"
    elif [[ -n "${OPT_WINE_ARCHIVE:-}" ]]; then
        warn "チェックサム(.sha256)が無いので、指定された配布ファイルを確かめられませんでした"
    else
        die "Wine の配布ファイルのチェックサム(.sha256)がありません: $archive"
    fi

    name="$(basename "$archive" .tar.xz)"
    if [[ ! -x "$CLISTUX_DATA/$name/bin/wine" ]]; then
        info "Wine を展開しています…"
        rm -rf "$CLISTUX_DATA/$name.partial"
        mkdir -p "$CLISTUX_DATA/$name.partial"
        run_logged tar -xJf "$archive" -C "$CLISTUX_DATA/$name.partial" --strip-components=1 || die "Wine の展開に失敗しました。"
        mv "$CLISTUX_DATA/$name.partial" "$CLISTUX_DATA/$name"
    fi
    # 使う Wine を切り替える。古い版のフォルダーは、動作を確かめた後に update が片付ける。
    ln -sfn "$name" "$WINE_DIR"
    ok "Wine: $name"
}

# 使っていない古い Wine を消す
prune_old_wine() {
    local current d
    current="$(readlink "$WINE_DIR" 2>/dev/null)" || return 0
    for d in "$CLISTUX_DATA"/wine-*-csp*-x86_64; do
        [[ -d "$d" && "$(basename "$d")" != "$current" ]] || continue
        rm -rf "$d" && info "古い Wine を片付けました: $(basename "$d")"
    done
}
