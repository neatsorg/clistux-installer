#!/usr/bin/env bash
# ツールのリリースに置くファイルを作る: clistux.tar.gz、release.json、install.sh
#
# 使い方: scripts/make-release.sh [出力先]
#   版は data/VERSION から読む。tar の中身は、作った日時や持ち主によらず同じになるようにそろえる。
#   TOOL_URL_BASE で、release.json に書く clistux.tar.gz の置き場所を変えられる(試験用。既定は GitHub Releases の v<版>)。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/data/VERSION")"
OUT="${1:-$ROOT/dist/v$VERSION}"
URL_BASE="${TOOL_URL_BASE:-https://github.com/neatsorg/clistux-installer/releases/download/v$VERSION}"
NAME="clistux-$VERSION"
EPOCH="$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || echo 0)"

rm -rf "$OUT" && mkdir -p "$OUT"
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$NAME"
# 利用者に要るものだけを入れる(Wine のビルド・試験・文書の下書きは入れない)
cp -r "$ROOT/clistux" "$ROOT/install.sh" "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/lib" "$ROOT/integration" "$ROOT/data" "$stage/$NAME/"
find "$stage/$NAME" -name '__pycache__' -prune -exec rm -rf {} +

tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner -C "$stage" -cf - "$NAME" \
    | gzip -n -9 > "$OUT/clistux.tar.gz"
sum="$(sha256sum "$OUT/clistux.tar.gz" | cut -d' ' -f1)"
cp "$ROOT/install.sh" "$OUT/install.sh"
cat > "$OUT/release.json" <<JSON
{
  "version": "$VERSION",
  "tool_url": "$URL_BASE/clistux.tar.gz",
  "tool_sha256": "$sum"
}
JSON
echo "作りました: $OUT"
ls -l "$OUT"
