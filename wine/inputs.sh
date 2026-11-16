# shellcheck shell=bash
# ビルドの入力を固定する(wine/build.sh・wine/build-unix.sh・integration/wv2check/build.sh が読む)。
# 版を上げるときは、ここを書き換えてから、ビルドし直して動作を確かめる。

# コンテナのイメージ(digest で固定)
IMAGE_ALMA="docker.io/library/almalinux@sha256:1965cb10f9c392766b2d544d3c1b997eb008d0e413c808e6a20086e87c802a80"   # almalinux:8
IMAGE_DEBIAN="docker.io/library/debian@sha256:268fb24c39bca92d326dd83ea3abebe4a3f7751c804ffef23bb6d857dd343ff8"    # debian:12

# Wine の公式のソースのチェックサム(版ごと)
declare -A WINE_SOURCE_SHA256=(
    [11.4]=1970a46381d3bc2c44d651d08336370e499eeb8b53dc93cbd1ce544f7115e598
)

# Wine の公式のソースを取得してチェックサムを確かめ、置き場所を返す
fetch_wine_source() {
    local ver="$1" dir="$2" major sum file
    major="${ver%%.*}"
    sum="${WINE_SOURCE_SHA256[$ver]:-}"
    [[ -n "$sum" ]] || { echo "エラー: Wine $ver のソースのチェックサムが wine/inputs.sh にありません" >&2; return 1; }
    file="$dir/wine-$ver.tar.xz"
    mkdir -p "$dir"
    if [[ ! -f "$file" ]] || ! echo "$sum  $file" | sha256sum -c --status -; then
        curl -fsSL --proto '=https' -o "$file.part" "https://dl.winehq.org/wine/source/${major}.x/wine-$ver.tar.xz" || return 1
        echo "$sum  $file.part" | sha256sum -c --status - || { rm -f "$file.part"; echo "エラー: Wine のソースのチェックサムが合いません" >&2; return 1; }
        mv "$file.part" "$file"
    fi
    echo "$file"
}
