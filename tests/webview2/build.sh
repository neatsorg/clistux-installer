#!/usr/bin/env bash
# wv2probe.exe をビルドする。Wine のビルド用ディレクトリ(wine/dev.sh setup で作るもの)の winegcc を使う。
# WebView2 SDK(NuGet の Microsoft.Web.WebView2 1.0.3179.45、BSD ライセンス)を取得し、
# ヘッダーと x64 の WebView2Loader.dll を取り出して使う。
set -euo pipefail

CACHE="${CLISTUX_CACHE:-$HOME/.cache/clistux}"
SRC="$CACHE/wine-src"
BUILD="$CACHE/wine-build"
SDK_VERSION=1.0.3179.45
SDK_SHA256=70bd381c5d67f97a6a80294001cde125ab5b24b6d36098ad901d8e15efd752d0
SDK="$CACHE/webview2-sdk"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SDK/build/native/include/WebView2.h" ]]; then
    mkdir -p "$SDK"
    pkg="$SDK/microsoft.web.webview2.$SDK_VERSION.nupkg"
    curl -sSL --fail -o "$pkg" \
        "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$SDK_VERSION/microsoft.web.webview2.$SDK_VERSION.nupkg"
    echo "$SDK_SHA256  $pkg" | sha256sum -c -
    (cd "$SDK" && unzip -oq "$pkg" 'build/native/include/*' 'build/native/x64/WebView2Loader.dll' LICENSE.txt NOTICE.txt)
fi

# WebView2.h は "EventToken.h" を読むが、Wine のヘッダーは小文字の eventtoken.h
make -C "$BUILD" include/eventtoken.h dlls/ole32/x86_64-windows/libole32.a dlls/user32/x86_64-windows/libuser32.a \
    dlls/kernel32/x86_64-windows/libkernel32.a > /dev/null
mkdir -p "$SDK/compat"
ln -sf "$BUILD/include/eventtoken.h" "$SDK/compat/EventToken.h"

"$BUILD/tools/winegcc/winegcc" --wine-objdir "$BUILD" -b x86_64-windows -mconsole \
    -o "$HERE/wv2probe.exe" "$HERE/wv2probe.c" \
    -I"$BUILD/include" -I"$SRC/include" -I"$SRC/include/msvcrt" -I"$SDK/build/native/include" -I"$SDK/compat" \
    -D_UCRT -Wno-nonportable-include-path -lole32 -luser32 -lkernel32 -luuid -lucrtbase
install -m 644 "$SDK/build/native/x64/WebView2Loader.dll" "$HERE/WebView2Loader.dll"
echo "ビルドしました: $HERE/wv2probe.exe(WebView2Loader.dll も同じフォルダーに置きました)"
