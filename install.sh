#!/usr/bin/env bash
# Clistux Installer の導入の入口。次の1行で動かす:
#   curl -fsSL https://github.com/neatsorg/clistux-installer/releases/latest/download/install.sh | bash
#
# 最新のリリースからツール本体(clistux.tar.gz)を取得し、チェックサムを確かめて展開し、導入(clistux install)を始める。
# このスクリプトに渡した引数は、そのまま clistux install に渡す(例: --csp-installer ファイル)。
# 試験のときは CLISTUX_RELEASE_BASE で、取得元を手元のフォルダ(file://…)などに差し替えられる。
#
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

BASE="${CLISTUX_RELEASE_BASE:-https://github.com/neatsorg/clistux-installer/releases/latest/download}"
PROTO='=https'
[[ -n "${CLISTUX_RELEASE_BASE:-}" ]] && PROTO='=https,file'

say()  { printf '%s\n' "$*"; }
fail() {
    printf '\nうまくいきませんでした: %s\n' "$1" >&2
    [[ -n "${2:-}" ]] && printf '  %s\n' "$2" >&2
    exit 1
}

for c in curl tar gzip sha256sum sed mktemp; do
    command -v "$c" > /dev/null || fail "基本のコマンド「$c」がありません。" "ディストリビューションの基本パッケージを入れてから、もう一度実行してください。"
done
[[ "$(uname -m)" == x86_64 ]] || fail "この PC の CPU($(uname -m))には対応していません。"
[[ $EUID -ne 0 ]] || fail "root(管理者)のままでは実行できません。" "sudo を付けずに実行してください。"

tmp="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/clistux-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

say "Clistux Installer を入手しています…"
curl -fsSL --proto "$PROTO" --proto-redir '=https' --retry 3 -o "$tmp/release.json" "$BASE/release.json" \
    || fail "リリースの情報を取得できませんでした。" "インターネットにつながっているか確かめてください。"
get() { sed -n "s/.*\"$1\": *\"\\([^\"]*\\)\".*/\\1/p" "$tmp/release.json" | head -1; }
version="$(get version)"; url="$(get tool_url)"; sum="$(get tool_sha256)"
[[ -n "$version" && -n "$url" && -n "$sum" ]] || fail "リリースの情報を読めませんでした。"

curl -fsSL --proto "$PROTO" --proto-redir '=https' --retry 3 -o "$tmp/clistux.tar.gz" "$url" \
    || fail "ツール本体を取得できませんでした。" "インターネットにつながっているか確かめてください。"
echo "$sum  $tmp/clistux.tar.gz" | sha256sum -c --status - \
    || fail "取得したツール本体が壊れています。" "もう一度実行してください。"
mkdir -p "$tmp/clistux"
tar -xzf "$tmp/clistux.tar.gz" -C "$tmp/clistux" --strip-components=1 || fail "ツール本体を展開できませんでした。"
say "Clistux Installer $version を入手しました。"
echo

# 「curl … | bash」で動かすと、キーボードの入力がこのスクリプトに届かない。
# 確認の質問に答えられるように、入力を端末につなぎ直してから導入を始める。
if [[ ! -t 0 ]] && { true < /dev/tty; } 2> /dev/null; then
    "$tmp/clistux/clistux" install "$@" < /dev/tty
else
    "$tmp/clistux/clistux" install "$@"
fi
