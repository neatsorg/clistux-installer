# shellcheck shell=bash
# リリースの取り決め: このツールの版、使う Wine、公開先。
#
# ツールのリリース(タグ v<版>)には次を置く:
#   install.sh     端末に貼り付ける1行で動かす、導入の入口
#   clistux.tar.gz このツール本体
#   release.json   {"version": "<版>", "tool_url": "<clistux.tar.gz の URL>", "tool_sha256": "<チェックサム>"}
# Wine のリリース(タグ wine-<版>-csp<リビジョン>)には、パッチ入りの Wine と、そのソース・パッチを置く。
# どの Wine を使うかは、ツールの data/wine-release に名前・URL・チェックサムで書く。

RELEASE_REPO="neatsorg/clistux-installer"
# 試験のときは CLISTUX_RELEASE_BASE で、手元のフォルダ(file://…)などに差し替えられる
RELEASE_BASE="${CLISTUX_RELEASE_BASE:-https://github.com/$RELEASE_REPO/releases/latest/download}"

tool_version() { cat "$CLISTUX_ROOT/data/VERSION" 2>/dev/null || echo 0; }

wine_release_get() { sed -n "s/^$1=//p" "$CLISTUX_ROOT/data/wine-release"; }

# ダウンロード。公開先は https だけ。試験で差し替えたときは file:// も使える。
fetch() {
    local url="$1" out="$2" proto='=https'
    [[ -n "${CLISTUX_RELEASE_BASE:-}" ]] && proto='=https,file'
    curl -fL --proto "$proto" --proto-redir '=https' --retry 3 -o "$out" "$url"
}

# 版の比べ方(1.2.10 > 1.2.9)。第1引数のほうが新しければ成功
version_newer() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]; }

# release.json から値を1つ取り出す(このツールが作る、1行に1つの単純な形だけを読む)
json_get() { sed -n "s/.*\"$1\": *\"\\([^\"]*\\)\".*/\\1/p" "$2" | head -1; }

# 新しい版のツールがあれば取得して確かめ、新しいツールで同じコマンドを続ける。無ければ何もしない。
self_update() {
    [[ -n "${CLISTUX_SELF_UPDATED:-}" ]] && return 0
    local tmp json ver url sum
    tmp="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/clistux-update.XXXXXX")"
    json="$tmp/release.json"
    info "このツールの新しい版を調べています…"
    if ! fetch "$RELEASE_BASE/release.json" "$json" >> "$LOG" 2>&1; then
        warn "新しい版を調べられませんでした(インターネットにつながっているか確かめてください)。今の版のまま続けます。"
        rm -rf "$tmp"; return 0
    fi
    ver="$(json_get version "$json")"; url="$(json_get tool_url "$json")"; sum="$(json_get tool_sha256 "$json")"
    if [[ -z "$ver" || -z "$url" || -z "$sum" ]]; then
        warn "公開先の情報を読めませんでした。今の版のまま続けます。"
        rm -rf "$tmp"; return 0
    fi
    if ! version_newer "$ver" "$(tool_version)"; then
        ok "このツールは最新です($(tool_version))"
        rm -rf "$tmp"; return 0
    fi
    info "新しい版($ver)を入手しています…"
    fetch "$url" "$tmp/clistux.tar.gz" >> "$LOG" 2>&1 || die "新しい版のダウンロードに失敗しました。"
    echo "$sum  $tmp/clistux.tar.gz" | sha256sum -c --status - || die "ダウンロードした新しい版が壊れています。" "もう一度実行してください。"
    mkdir -p "$tmp/new"
    tar -xzf "$tmp/clistux.tar.gz" -C "$tmp/new" --strip-components=1 || die "新しい版を展開できませんでした。"
    ok "このツールを $(tool_version) から $ver にします"
    # 新しい版のツールで、同じコマンドを続ける(新しい Wine・設定・ツール自身の配置は新しい版が行う)
    CLISTUX_SELF_UPDATED=1 CLISTUX_RELOCATED="$tmp" exec "$tmp/new/clistux" "${ORIG_ARGS[@]}"
}
