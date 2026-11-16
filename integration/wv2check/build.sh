#!/usr/bin/env bash
# wv2check.exe を mingw-w64 の GCC でビルドする(コンテナの Debian 12)。
# WebView2 SDK(NuGet の Microsoft.Web.WebView2、BSD ライセンス)からヘッダーと x64 の WebView2Loader.dll を取り出して使う。
#
# 使い方: integration/wv2check/build.sh [出力先のフォルダー]
#   出力: wv2check.exe、WebView2Loader.dll、WebView2-LICENSE.txt
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-${CLISTUX_CACHE:-$HOME/.cache/clistux}/wv2check}"
SDK_VERSION=1.0.3179.45
SDK_SHA256=70bd381c5d67f97a6a80294001cde125ab5b24b6d36098ad901d8e15efd752d0

if command -v podman >/dev/null 2>&1; then CTR=podman
elif command -v docker >/dev/null 2>&1; then CTR=docker
else echo "エラー: podman か docker が必要です" >&2; exit 1; fi

mkdir -p "$OUT"
# shellcheck disable=SC2086
"$CTR" ${CTR_GLOBAL_OPTS:-} run ${CTR_RUN_OPTS:-} --rm -i \
    -v "$HERE:/src:ro,z" -v "$OUT:/out:z" \
    -e SDK_VERSION="$SDK_VERSION" -e SDK_SHA256="$SDK_SHA256" \
    docker.io/library/debian:12 bash -euo pipefail -s << 'BUILD'
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install -y --no-install-recommends gcc-mingw-w64-x86-64 curl ca-certificates unzip > /dev/null
cd /tmp
curl -fsSL -o sdk.nupkg "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$SDK_VERSION/microsoft.web.webview2.$SDK_VERSION.nupkg"
echo "$SDK_SHA256  sdk.nupkg" | sha256sum -c - > /dev/null
unzip -oq sdk.nupkg 'build/native/include/*' 'build/native/x64/WebView2Loader.dll' LICENSE.txt
# WebView2.h は "EventToken.h" を読むが、mingw-w64 のヘッダーは小文字
mkdir -p compat && ln -sf /usr/share/mingw-w64/include/eventtoken.h compat/EventToken.h
x86_64-w64-mingw32-gcc -O2 -municode -mconsole -o /out/wv2check.exe /src/wv2check.c \
    -Ibuild/native/include -Icompat -lole32 -luuid
install -m 644 build/native/x64/WebView2Loader.dll /out/WebView2Loader.dll
install -m 644 LICENSE.txt /out/WebView2-LICENSE.txt
echo "ビルドしました: wv2check.exe"
BUILD
ls -l "$OUT"
