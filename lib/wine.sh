# shellcheck shell=bash
# Wine の入手と配置。
# 配る Wine は wine/build.sh で作ったもの(公式のソース + このプロジェクトのパッチ)。
# どの Wine を使うかは data/wine-release に、名前・URL・チェックサムで決めてある(lib/release.sh)。
# 入手先: --wine-archive で渡したファイル、なければ手元のキャッシュ、なければ公開先からダウンロード。
# どこから得たものも、data/wine-release のチェックサムで確かめる(--wine-archive で渡したものを除く)。

install_wine() {
    local name url sum archive
    name="$(wine_release_get WINE_NAME)"
    url="$(wine_release_get WINE_URL)"
    sum="$(wine_release_get WINE_SHA256)"
    [[ -n "$name" && -n "$url" && -n "$sum" ]] || die "このツールの中の Wine の情報(data/wine-release)が足りません。"

    if [[ -n "${OPT_WINE_ARCHIVE:-}" ]]; then
        # 開発・試験のため。チェックサムが合わなくても使うが、そのことを知らせる
        archive="$OPT_WINE_ARCHIVE"
        [[ -f "$archive" ]] || die "指定された Wine の配布ファイルがありません: $archive"
        name="$(basename "$archive" .tar.xz)"
        echo "$sum  $archive" | sha256sum -c --status - || warn "指定された配布ファイルは、このツールが決めている Wine とは違います($name)"
    else
        archive="$CLISTUX_CACHE/dist/$name.tar.xz"
        if [[ ! -f "$archive" ]] || ! echo "$sum  $archive" | sha256sum -c --status -; then
            mkdir -p "$CLISTUX_CACHE/dist"
            info "Wine をダウンロードしています(約 200 MB)…"
            rm -f "$archive.part"
            # 一時的な名前で受け取り、チェックサムを確かめてから正式な名前にする(途中で失敗したものを次回に使わない)
            run_logged fetch "$url" "$archive.part" \
                || { rm -f "$archive.part"; die "Wine のダウンロードに失敗しました。" "インターネットにつながっているか確かめてください。"; }
            if ! echo "$sum  $archive.part" | sha256sum -c --status -; then
                rm -f "$archive.part"
                die "ダウンロードした Wine が壊れています。" "もう一度実行してください。"
            fi
            mv "$archive.part" "$archive"
        fi
        ok "Wine の配布ファイルを確かめました"
    fi

    # 展開したものには、元の配布ファイルのチェックサムを印として残す。同じ名前でも中身が違えば展開し直す。
    local have
    have="$(cat "$CLISTUX_DATA/$name/.clistux-sha256" 2>/dev/null || true)"
    if [[ ! -x "$CLISTUX_DATA/$name/bin/wine" || "$have" != "$(sha256sum "$archive" | cut -d' ' -f1)" ]]; then
        info "Wine を展開しています…"
        rm -rf "$CLISTUX_DATA/$name.partial"
        mkdir -p "$CLISTUX_DATA/$name.partial"
        run_logged tar -xJf "$archive" -C "$CLISTUX_DATA/$name.partial" --strip-components=1 || die "Wine の展開に失敗しました。"
        sha256sum "$archive" | cut -d' ' -f1 > "$CLISTUX_DATA/$name.partial/.clistux-sha256"
        rm -rf "$CLISTUX_DATA/$name"
        mv "$CLISTUX_DATA/$name.partial" "$CLISTUX_DATA/$name"
    fi
    # 使う Wine を切り替える。古い版のフォルダは、update が片付ける。
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
